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
#   - packet length fix by @mrsoap
#   - on the same subroutine (upgrade_list), change 13 to 23
#   - this line here -> for (my $i = 0; $i < length($args->{item_list}); $i += 13) {
#   - and this -> my ($index, $nameID) = unpack('a2 x6 C', substr($args->{item_list}, $i, 13));
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

use Time::HiRes;

use constant {
    TRUE => 1,
    FALSE => 0,
    REFINESTART => 2,
    REFINESELECT => 3,
    IDLE => 4,
    REFINE_DELAY => 0.1,
    REFINE_DELAY2 => 1,
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
my $common_time;

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
        if ($equip->name =~ $weaponMatch) {
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
    $actionState = REFINESTART;
}

sub refineList {
    my ($self, $args) = @_;
    my $refine_list = $args->{upgrade_list};
    my @upgradeList = @$refine_list;
    $actionState = REFINESELECT;
    debug "I am at refineList!\n";
    $common_time = time;
    foreach my $weaponData (@upgradeList) {
        my ($refineID, $itemName, $itemID) = @$weaponData;
        if (($itemName =~ $weaponMatch) && ($actionState eq REFINESELECT) && ($refiningStatus eq TRUE)) {
            debug "$itemName\n";
            if (($1 < $refineAmount) && ($2 eq $weapon)) {
                debug "weapon $weapon is refined to $1\n";
                $messageSender->sendWeaponRefine($refineList->[$refineID]);
                $actionState = REFINESTART;
            }
        }
    }
}

sub refineMain {
    while ((timeOut($common_time, REFINE_DELAY)) && ($refiningStatus eq TRUE) && ($actionState eq REFINESTART)) {
        $common_time = time;
        message "Refining ", 'system';
        message "$weapon ", 'success';
        message "up to +", 'system';
        message "$refineAmount\n", 'success';

        $messageSender->sendSkillUse(477, $char->{skills}{WS_WEAPONREFINE}{lv}, $accountID);
        $actionState = REFINESELECT;
    }
}
1;
