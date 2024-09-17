package weaponRefine;
#   weaponRefine - Whitesmith Weapon Refining plugin by Isora/kw4k
#   https://github.com/kw4k/openkore-plugins
#
# look for the subroutine 'upgrade_list' in src\Network\Receive.pm
# look and add the following:
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
#   TODO:
#       - work on ss 477
#       - work on selective refining
#       - check other TODOs

use strict;
use Plugins;
use Log qw(message error);
use Utils;
use Actor;
use AI;
use Globals;
use Skill;
use Network;
use Misc;

use constant {
    TRUE => 1,
    FALSE => 0,
};

Plugins::register("weaponRefine", "weaponRefine - Whitesmith weapon refine plugin. ", \&onUnload, \&onReload);

my $hooks = Plugins::addHooks(
    ["upgrade_list", \&refineList, undef],
    ["AI_pre", \&refineMain, undef],
);

my $commands = Commands::register(
    ['weaponRefine', 'weaponRefine usage', \&commandHelp],
	['setWeapon', 'sets the weapon to be refined', \&setWeapon],
    ['setRefine', 'sets the weapon refine limit', \&setRefineAmount],
    ['startRefine', 'start the refining process', \&startRefine],
    ['stopRefine', 'stops the refining process', \&stopRefine],
    ['test', 'test', \&testSkillUse],
);

message "weaponRefine loaded!\n\n", "success";
commandHelp();

# variables
our $weapon;
our $weaponSetStatus = FALSE;
our $refineAmount;
our $refiningStatus = FALSE;

sub onUnload {
    Plugins::delHooks($hooks);
    Commands::unregister($commands);
    $weapon = undef;
    $refineAmount = undef;
    message "weaponRefine plugin unloaded.\n", 'success';
}

sub onReload {
    onUnload();
}

sub testSkillUse {
    Commands::run("ss 477 10");
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
    # TODO: make kore check cart and storage for weapons
    our ($weapon) = @_[1];

    message "Available weapons to be refined:\n\tItemID\tWeapon\n", "system";
    foreach my $equip (@{$char->inventory->getItems}) {
        if ($equip->name =~ /\+?(\d+)?\s*([A-Za-z\s\-]+(?:\[\d*\])?)/) {
            if ($2 eq $weapon) {
                message "\t[$equip->{binID}]\t$equip\n", "success";
                $weaponSetStatus = TRUE if !$weaponSetStatus;
            }
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
    } else {
        error "Please check your setWeapon and/or setRefine.\n";
    }
}

sub stopRefine {
    $refiningStatus = FALSE;
    message "Weapon Refining stopped.\n", "drop";
}

sub refineList {
    # TODO:
    #   - parse refineID based on setWeapon and/or binID/itemID
    #   - track refine levels based on setRefine
    #   - make sure that it refines the right weapon (name and refine levels)
    my ($self, $args) = @_;

    my $refine_list = $args->{upgrade_list};
    my @upgradeList = @$refine_list;

    foreach my $weaponData (@upgradeList) {
        my ($refineID, $itemName, $itemID) = @$weaponData;
        
        if ($itemName =~ /\+?(\d+)?\s*([A-Za-z\s\-]+(?:\[\d*\])?)/) {
            if (($1 < $refineAmount) && ($2 eq $weapon)) {
                Commands::run("refine $refineID");
                #sleep(0.1);
                $weaponSetStatus = TRUE;
                startRefine();
                last;
            }
        }
        #message(sprintf("Refine ID: %s, Name: %s, Item ID: %s\n", $refineID, $itemName, $itemID), "list");
    }
}

sub refineMain {
    if ($refiningStatus eq TRUE) {
        # TODO:
        #   - main refine stuff
        #   - get refine stones from storage or npc
        #   - log successful attempt (beyond safe limits only)
        #   - humanlike refining aka spamming
        #   - make it work like with refineEquip macro. I like that one.
        message "Refining ", 'system';
        message "$weapon ", 'success';
        message "up to +", 'system';
        message "$refineAmount\n", 'success';

        Commands::run("ss 477 10");
        #sleep(0.1);
        $refiningStatus = FALSE;
    }
}

1;
