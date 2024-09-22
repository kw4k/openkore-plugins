package weaponRefine;
#   weaponRefine - Whitesmith Weapon Refining plugin by Isora/kw4k
#   https://github.com/kw4k/openkore-plugins
#
#   IMPORTANT:
#   - search the subroutine 'upgrade_list' in src\Network\Receive.pm
#   - look and add the following:
#   look for -> my $msg;
#   add below it -> my @upgradeList;
#
#   look for -> $msg .= swrite(sprintf("\@%s - \@%s (\@%s)", ('<'x2), ('<'x50), ('<'x3)), [$k, itemName($item), $item->{binID}]);
#   add below it -> push @upgradeList, [$k, itemName($item), $item->{binID}];
#
#   look for -> message T("You can now use the 'refine' command.\n"), "info";
#   add below it -> Plugins::callHook('upgrade_list', {
#		upgrade_list => \@upgradeList,
#	});
#
#   TODO/FIXME:
#   - cleaner loop
#   - fix weapon upgrade fail breaking a subroutine. apparently, [done]
#   - add filter for inventory_item_removed hook



use strict;
use Plugins;
use Log qw(message error debug);
use Utils;
use Actor;
use AI;
use Globals;
use Network;
use Network::Send;
use Misc;

use constant {
    TRUE => 1,
    FALSE => 0,
    REFINESTART => 2,
    REFINESELECT => 3,
    IDLE => 4,
};

Plugins::register("weaponRefine", "weaponRefine - Whitesmith weapon refine plugin. ", \&onUnload, \&onReload);

my $hooks = Plugins::addHooks(
    ["upgrade_list", \&refineList, undef],
    ["AI_pre", \&refineMain, undef],
    ["inventory_item_removed", \&itemRemoved, undef],
);

my $commands = Commands::register(
    ['weaponRefine', 'weaponRefine usage', \&commandHelp],
	['setWeapon', 'sets the weapon to be refined', \&setWeapon],
    ['setRefine', 'sets the weapon refine limit', \&setRefineAmount],
    ['startRefine', 'start the refining process', \&startRefine],
    ['stopRefine', 'stops the refining process', \&stopRefine],
    #['test', 'test', \&testSkillUse],
    ['test', 'test', \&testRegex],
);

message "weaponRefine loaded!\n\n", "success";
commandHelp();

# variables
our $weapon;
our $weaponInInventory = FALSE;
our $weaponlist;
our $weaponSetStatus = FALSE;
our $refineAmount;
our $refiningStatus = FALSE;
our $actionState = IDLE;

# i'll put regex here so it's easier to update
#our $weaponMatch = qr/\+?(\d+)?\s*([A-Za-z\s\-\']+(?:\[\d*\])?)/;
our $weaponMatch =  qr/\+?(\d+)?\s*([A-Za-z\s\-\']+(?:\[[A-za-z]*\d*\])?)/;

sub onUnload {
    Plugins::delHooks($hooks);
    Commands::unregister($commands);
    $weapon = undef;
    $refineAmount = undef;
    $weaponlist = undef;
    message "weaponRefine plugin unloaded.\n", 'success';
}

sub onReload {
    onUnload();
}

sub testSkillUse {
    Commands::run("ss 477 10");
}

sub testRegex {
    my ($arg) = @_[1];
    if ($arg =~ $weaponMatch) {
        debug "Yeah it works.\n"
    }
}

sub commandHelp {
    # help stuff
    message "\tweaponRefine - Whitesmith Weapon Refining plugin by Isora/kw4k\n\thttps://github.com/kw4k/openkore-plugins\n\n", 'menu';
    message "COMMANDS:\n", 'system';
    message "\tsetWeapon - sets the weapon to be refined\n";
    message "\tsetRefine - sets the weapon refine limit\n";
    message "\tstartRefine - start the refining process\n";
    message "\tstopRefine - stops the refining process\n";
    message "EXAMPLE:\n", 'system';
    message "\tsetWeapon Orcish Axe [4]\n\tsetRefine 7\n\n";
}

sub setWeapon {
    # TODO: 
    #   - make kore check cart and storage for weapons
    #   - reset setRefine when setting new weapon [done]
    # FIXME:
    #   - this whole setWeapon stuff. when setWeapon takes no argument, 
    #   i want it to display the current weaponlist and weapon if it has data in it,
    #   and an error if there's nothing. just purely aesthetic.
    #   
    my ($arg) = @_[1];
    $refineAmount = undef;

    if (!$arg) {
        if ($weapon && $weaponlist && ($weaponInInventory ne FALSE)) {
            message "\tThe current weapon(s) available for refinement: ", "system";
            message "$weapon\n", "success";
            debug "$weaponSetStatus\n";
        } else {
            debug "Fail1\n";
            error "\tPlease set a weapon to be refined\n";
        }
    } else {
        findAndSetWeapon($arg);
        if (($weaponInInventory eq TRUE) && ($arg eq $weapon)) {
            message "Available weapons to be refined:\n\tItemID\tWeapon\n", "system";
            message $weaponlist, "success";
            $weaponSetStatus = TRUE;
            debug "$weaponSetStatus\n";
        } else {
            debug "Fail2\n";
            debug "$weapon\n";
            message "\tWeapon not found\n", "drop";
            undef $weaponInInventory;
        }
    }

}

sub findAndSetWeapon {
    # TODO/FIXME:
    #   - yeah might change this but it works for now. 
    my ($arg) = @_;
    undef $weaponlist;
    foreach my $equip (@{$char->inventory->getItems}) {
        if ($equip->name =~ /\+?(\d+)?\s*([A-Za-z\s\-\']+(?:\[\d*\])?)/) {
            if ($2 eq $arg) {
                $weaponlist .= "\t[$equip->{binID}]\t$equip\n";
                $weapon = $arg;
                $weaponInInventory = TRUE if !$weaponInInventory;
                $weaponSetStatus = TRUE if !$weaponSetStatus;
            }
        } else {
            $weaponInInventory = FALSE if !$weaponInInventory;
            $weaponSetStatus = FALSE;
            last;
        }
    }
}

sub setRefineAmount {
    # TODO: determine weapon safe refine limit for each weapon level (1-4)
    # use the one I used for refineEquip macro
    our ($refineAmount) = @_[1];

    if ($refineAmount =~ /^\d+$/ && $refineAmount >= 1 && $refineAmount <= 10) {
        message "Refine Limit set to: +$refineAmount.\n", "success";
    } else {
        error "Invalid refine amount. Please enter a number between 1 and 10.\n";
    }
}

sub startRefine {
    if (($weaponSetStatus eq TRUE) && ($refineAmount)) {
        message "Weapon Refining start!\n", "success";
        $refiningStatus = TRUE;
        $actionState = REFINESTART;
    } else {
        error "Please check your setWeapon and/or setRefine.\n";
    }
}

sub stopRefine {
    $refiningStatus = FALSE;
    $actionState = IDLE;
    message "Weapon Refining stopped.\n", "drop";
}

sub itemRemoved {
    # TODO: add filter for items currently being refined to avoid triggering unrelated
    #   inventory_item_removed hooks.
    $actionState = REFINESTART;
}

sub refineList {
    # FIXME: 
    #   - program breaks when weapon gets destroyed due to failed upgrade [done]
    my ($self, $args) = @_;
    my $refine_list = $args->{upgrade_list};
    my @upgradeList = @$refine_list;
    $actionState = REFINESELECT;
    debug "I am at refineList!\n";
    foreach my $weaponData (@upgradeList) {
        my ($refineID, $itemName, $itemID) = @$weaponData;
        if (($itemName =~ /\+?(\d+)?\s*([A-Za-z\s\-\']+(?:\[\d*\])?)/) && ($actionState eq REFINESELECT) && ($refiningStatus eq TRUE)) {
            debug "$itemName\n";
            if (($1 < $refineAmount) && ($2 eq $weapon)) {
                debug "weapon $weapon is refined to $1\n";
                $messageSender->sendWeaponRefine($refineList->[$refineID]);
                $actionState = REFINESTART;
                #sleep(0.1);
                #last;
            }
        }
    }
}

sub refineMain {
    while (($refiningStatus eq TRUE) && ($actionState eq REFINESTART)) {
        message "Refining ", 'system';
        message "$weapon ", 'success';
        message "up to +", 'system';
        message "$refineAmount\n", 'success';

        $messageSender->sendSkillUse(477, $char->{skills}{WS_WEAPONREFINE}{lv}, $accountID);
        $actionState = REFINESELECT;
        #sleep(0.1);
    }
}
1;
