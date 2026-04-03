proc hier {hier_fh cell_fh} {
    set main_hier_dict {}
    set cell_mapping_dict {}
    set cell_name_list {}
    
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
                    dict set main_hier_dict $slr $cr $tile $site {}

                    set cell_list [get_cells -of_object $site]
                    foreach cell $cell_list {
                        dict set cell_mapping_dict [list $slr $cr $tile $site $cell] $cell
                        lappend cell_name_list [get_property REF_NAME $cell]
                        puts $cell_fh "Cell: $cell -> SLR: $slr -> CR:$cr -> TILE: $tile -> SITE: $site"
                    }
                    
                    set bel_list [get_bels -of_objects $site]
                    foreach bel $bel_list {
                        dict set main_hier_dict $slr $cr $tile $site $bel {}
                    }
                }
            }
        }
    }
    puts $cell_fh "============================================================================================================================"
    puts $cell_fh "CELL COUNTER"
    puts $cell_fh "============================================================================================================================"
    set cell_dict {}
    foreach cell_name $cell_name_list {
        dict incr cell_dict $cell_name 1
    }
    dict for {name count} $cell_dict {
        puts $cell_fh "Cell Name: $name: $count"
    }
    set slr_loc_count {}
    set cr_loc_count {}
    set tile_loc_count {}
    set site_loc_count {}
    puts $cell_fh "============================================================================================================================"
    puts $cell_fh "CELL MAPPING (each section should add up to same count)"
    puts $cell_fh "============================================================================================================================"

    dict for {loc cell_name} $cell_mapping_dict {
        set slr_loc [lindex $loc 0]
        set cr_loc [lindex $loc 1]
        set tile_loc [lindex $loc 2]
        set site_loc [lindex $loc 3]

        dict incr slr_loc_count $slr_loc 1
        dict incr cr_loc_count [list $slr_loc $cr_loc] 1
        dict incr tile_loc_count [list $slr_loc $cr_loc $tile_loc] 1
        dict incr site_loc_count [list $slr_loc $cr_loc $tile_loc $site_loc] 1
    }

    dict for {name count} $slr_loc_count {
        puts $cell_fh "SLR: $name: $count"
    } 
    dict for {name count} $cr_loc_count {
        puts $cell_fh "CR: $name: $count"
    } 
    dict for {name count} $tile_loc_count {
        puts $cell_fh "TILE: $name: $count"
    } 
    dict for {name count} $site_loc_count {
        puts $cell_fh "SITE: $name: $count"
    } 
    puts $hier_fh "FPGA Architecture: $main_hier_dict"
    return [list $main_hier_dict]
}

proc location {grid_fh} {
    set site_list [get_sites]
    set min_rpm_x [lindex [lsort -integer [get_property RPM_X $site_list]] 0]
    set max_rpm_x [lindex [lsort -integer [get_property RPM_X $site_list]] end]
    set min_rpm_y [lindex [lsort -integer [get_property RPM_Y $site_list]] 0]
    set max_rpm_y [lindex [lsort -integer [get_property RPM_Y $site_list]] end]
    puts $grid_fh "RPM_X min: $min_rpm_x and RPM_X max is $max_rpm_x"
    puts $grid_fh "RPM_Y min: $min_rpm_y and RPM_Y max is $max_rpm_y"
    
    #get cells prints: VCC clk_IBUF_BUFG_inst clk_IBUF_inst ext_rst_IBUF_inst pll_out_OBUF_inst ref_sig_IBUF_inst u_lf u_nco u_pd
    set input_site [get_sites -of_object [get_cells ref_sig_IBUF_inst]]
    set input_site_cr [get_clock_regions -of_objects $input_site]
    set closest_site [lindex [get_sites -filter "SITE_TYPE =~ SLICE* && !IS_USED " -of_objects $input_site_cr] 0]
    #grab cell that is connected to input and output pins of ref_sig
    set ref_cell [get_cells -of_objects [get_pins -leaf -filter "REF_PIN_NAME == D && DIRECTION == IN" -of_objects [get_nets -of_objects [get_pins ref_sig_IBUF_inst/O]]]]
    set cmp_cell [get_cells -filter {IS_SEQUENTIAL} -of_objects [get_pins -leaf -filter "DIRECTION == OUT" -of_objects [get_nets -of_objects [get_pins pll_out_OBUF_inst/I]]]]

    set_property LOC $closest_site $ref_cell
    set_property BEL AFF $ref_cell

    set_property LOC $closest_site $cmp_cell
    set_property BEL BFF $cmp_cell

    place_design
    route_design

    #unrouted info
    #set b_skew [expr abs($b_ref - $b_cmp)] is 0.938
    #compared signal delay should be longer bc its a feedback signal compared to asynch signal like ref
    set ref_path [get_timing_paths -to [get_pins $ref_cell/D]]
    set cmp_path [get_timing_paths -to [get_pins $cmp_cell/D]]
    set ref_delay [get_property DATAPATH_DELAY $ref_path]
    set cmp_delay [get_property DATAPATH_DELAY $cmp_path]
    set physical_skew [expr abs($ref_delay - $cmp_delay)]
    puts $grid_fh "------------------------------------------------"
    puts $grid_fh "PHYSICAL AUDIT RESULTS:"
    puts $grid_fh "Reference Register Delay: $ref_delay"
    puts $grid_fh "Compared Register Delay: $cmp_delay"
    puts $grid_fh "Total Path Skew: $physical_skew"
    puts "------------------------------------------------"
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

        if {[regexp {\|\s*Block RAM Tile\s*\|\s*([0-9]+)\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*([0-9]+)\s*\|\s*([0-9.]+)\s*\|} $line -> used_BRAM avail_BRAM util_BRAM]} {
            puts $resource_fh "Used BRAM: $used_BRAM"
            puts $resource_fh "BRAM available: $avail_BRAM"
            puts $resource_fh "BRAM utilized: $util_BRAM"            
        }

        if {[regexp {\|\s*DSPs\s*\|\s*([0-9]+)\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*([0-9]+)\s*\|\s*([0-9.]+)\s*\|} $line -> used_dsp avail_dsp util_dsp]} {
            puts $resource_fh "Used DSPs: $used_dsp"
            puts $resource_fh "DSP available: $avail_dsp"
            puts $resource_fh "DSP utilized: $util_dsp"            
        }

        if {[regexp {\|\s*Bonded IOB\s*\|\s*([0-9]+)\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*([0-9]+)\s*\|\s*([0-9.]+)\s*\|} $line -> used_bi avail_bi util_bi]} {
            puts $resource_fh "Used Bonded IOB: $used_bi"
            puts $resource_fh "Bonded IOB available: $avail_bi"
            puts $resource_fh "Bonded IOB utilized: $util_bi"            
        }

        if {[regexp {\|\s*HPIOB_M\s*\|\s*([0-9]+)\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*([0-9]+)\s*\|\s*([0-9.]+)\s*\|} $line -> used_hpbim avail_hpbim util_hpbim]} {
            puts $resource_fh "Used HPIOB_M: $used_hpbim"
            puts $resource_fh "HPIOB_M available: $avail_hpbim"
            puts $resource_fh "HPIOB_M utilized: $util_hpbim"            
        }

        if {[regexp {\|\s*HPIOB_S\s*\|\s*([0-9]+)\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*([0-9]+)\s*\|\s*([0-9.]+)\s*\|} $line -> used_hpbis avail_hpbis util_hpbis]} {
            puts $resource_fh "Used Bonded HPIOB_S: $used_hpbis"
            puts $resource_fh "HPIOB_S available: $avail_hpbis"
            puts $resource_fh "HPIOB_S utilized: $util_hpbis"            
        }
    }
}
proc main {} {
    set hier_fh [open hier_file.txt "w"]
    set cell_fh [open cell_mapping.txt "w"]
    set grid_fh [open grid_info.txt "w"]
    set resource_fh [open resource_file.txt "w"]
    
    hier $hier_fh $cell_fh
    location $grid_fh
    #util $resource_fh

    close $hier_fh
    close $cell_fh
    close $resource_fh

}

main
