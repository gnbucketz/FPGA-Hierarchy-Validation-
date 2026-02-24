proc hier {hier_fh} {
    set main_hier_dict {}
    set secondary_hier_dict {}

    set slr_list [get_slrs]
    foreach slr $slr_list {
        dict set main_hier_dict $slr {}
        
        #set cr_list [get_clock_regions X0Y0]
        set cr_list [get_clock_regions -of_objects $slr]
        foreach cr $cr_list {
            dict set main_hier_dict $slr $cr {}
            
            set tile_list [get_tiles -of_objects $cr]
            #set tile_list [get_tiles -of_objects $cr -filter {TYPE =~ "*TILETYPE*"}]
            foreach tile $tile_list {
                dict set main_hier_dict $slr $cr $tile {}
                
                set site_list [get_sites -of_objects $tile]
                foreach site $site_list {
                    dict set secondary_hier_dict $tile $site {}

                    set bel_list [get_bels -of_objects $site]
                    foreach bel $bel_list {
                        dict set secondary_hier_dict $tile $site $bel {}
                    }
                }
            }
        }
    }
    puts $hier_fh "Main FPGA Architecture (SLR, CR, TILE): $main_hier_dict"
    puts $hier_fh "\nSecondary FPGA Architecture (SITE, BEL): $secondary_hier_dict"
    return [list $main_hier_dict $secondary_hier_dict]
}

proc util {resource_fh} {
    set mapping_dict {}
    report_utilization -slr -file util.rpt
    set util_fh [open util.rpt "r"]
    set readable_util_file [split [read $util_fh] "\n"]
    close $util_fh
    
    set desired_lut_info 0
    foreach line $readable_util_file {
        if {[string match "1. CLB Logic" $line]} {
            set desired_lut_info 1
        }
        
        if {[string match "2. CLB Logic Distribution" $line]} {
            set desired_lut_info 0
        }

        if {$desired_lut_info && [regexp {\|\s*CLB LUTs\s*\|\s*([0-9]+)\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*([0-9]+)\s*\|\s*([0-9.]+)\s*\|} $line -> lut_count lut_avail lut_pct]} {           
            puts $resource_fh "Total LUTs: $lut_count"
            puts $resource_fh "Total LUTs available: $lut_avail"
            puts $resource_fh "Total utilization percent: $lut_pct"
        }

        if {$desired_lut_info && [regexp {\|\s*LUT as Logic\s*\|\s*([0-9]+)\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*([0-9]+)\s*\|\s*([0-9.]+)\s*\|} $line -> l_lut_count l_lut_avail l_lut_pct]} {
            puts $resource_fh "Logic LUTs: $l_lut_count"
            puts $resource_fh "Total Logic LUTs available: $l_lut_avail"
            puts $resource_fh "Total Logic LUT utilization percent: $l_lut_pct"
        }

        if {$desired_lut_info && [regexp {\|\s*LUT as Memory\s*\|\s*([0-9]+)\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*([0-9]+)\s*\|\s*([0-9.]+)\s*\|} $line -> m_lut_count m_lut_avail m_lut_pct]} {
            puts $resource_fh "Memory LUTs: $m_lut_count"
            puts $resource_fh "Total Memory LUTs available: $m_lut_avail"
            puts $resource_fh "Total Memory LUT utilization percent: $m_lut_pct"
        }
    }
}
proc main {} {
    set hier_fh [open hier_file.txt "w"]
    set resource_fh [open resource_file.txt "w"]
    
    hier $hier_fh
    util $resource_fh

    close $hier_fh
    close $resource_fh
}

main