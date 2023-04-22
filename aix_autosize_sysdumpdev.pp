#
#  MODULE:      profile::aix_autosize_sysdumpdev
#
#  PURPOSE:     This function uses data from the cryssoft:aix_lvm_facts and
#		cryssoft::aix_sysdumpdev_facts modules to calculate the
#		required size of the primary system bump device and re-size it
#		if a) it's too small, and b) that volume group has enough space.
#
#  PARAMETERS:  (none)
#
#  NOTES:       All of the math assumes 1 PP per LP.  That ought to be a fairly
#		safe assumption in 2023, but there's an extra check to make sure.
#
#		This module coule be extended to deal with a secondary dump
#		device easily enough and to detect whether it's set for 
#		/dev/sysdumpnull or not.  That's not useful in the environment
#		where this is being developed.
#
#		This module doe not deal with the "copy directory".  Since that's
#		likely to be inside a file system and tough to correlate, we'll
#		leave that for another day.
#
#-------------------------------------------------------------------------------
#
#  AUTHOR:      Chris Petersen, Crystallized Software
#
#  DATE:        April 10, 2023
#
#  LAST MOD:    April 20, 2023
#
#-------------------------------------------------------------------------------
#
#  MODIFICATION HISTORY:
#
#  2023/04/20 - cp - Add some extra details to the failure messages.
#
class profile::aix_autosize_sysdumpdev {

    #  This particular implementation only applies to AIX systems
    if ($::facts['osfamily'] == 'AIX') {

        #  Gather a few basics about the primary dump device
        $pdd = $::facts['aix_sysdumpdev']['primary']
        $pddShort = split($pdd, '/')[-1]
        $pddEst = $::facts['aix_sysdumpdev']['estimated bytes']

        #  Make sure our primary sysdumpdev is a logical volume
        if ($pdd in $::facts['aix_lvs']) {

            #  Grab and calculate some data points about it
            $pddLPs = $::facts['aix_lvs'][$pdd]['lps_int']
            $pddPPs = $::facts['aix_lvs'][$pdd]['pps_int']
            $pddLPsMax = $::facts['aix_lvs'][$pdd]['max_lps_int']
            $pddPPSize = $::facts['aix_lvs'][$pdd]['pp_size_mb'] * 1024 * 1024
            $pddSize = $pddLPs * $pddPPSize
            $pddVG = $::facts['aix_lvs'][$pdd]['vg']

            #  If we're not in a 1:1 LP:PP ratio, this math won't work
            if ($pddLPs == $pddPPs) {

                #  If the estimate is bigger than the current size, we have a problem to solve
                if ($pddEst > $pddSize) {

                    #  How many PPs (total) do we need, and what's the delta
                    $pddLPsNeeded = (($pddEst - ($pddEst % $pddPPSize)) / $pddPPSize) + 1
                    $pddDelta = $pddLPsNeeded - $pddLPs

                    #
                    #  If the max LPs is greater than or equal to the needed, then this is 
                    #  safe at the LV layer
                    #
                    if ($pddLPsMax >= $pddLPsNeeded) {

                        #  If the VG has enough PPs to fulfill the request is completely safe
                        if ($::facts['aix_vgs'][$pddVG]['free_pps_pp'] >= $pddDelta) {

                            #  No built-in resources for this, so exec it
                            exec { "extendlv $pddShort $pddDelta":
                                command  => "/usr/sbin/extendlv $pddShort $pddDelta",
                                path     => '/bin:/sbin:/usr/bin:/usr/sbin:/etc',
                            }

                        }

                        #  The volume group doesn't have space, so give them a nice message
                        else {

                            $pddShortfall = $pddDelta - $::facts['aix_vgs'][$pddVG]['free_pps_pp']
                            notify { "VG $pddVG does not have space to extend LV $pdd for system dump - $pddShortfall PPs": }

                        }

                    }

                    #  We need to change the max size of the LV, so give them a nice message
                    else {

                        notify { "The maximum LPs ($pddLPsMax) is too small to extend LV $pdd for system dump": }

                    }

                }

            }

        }

    }

}
