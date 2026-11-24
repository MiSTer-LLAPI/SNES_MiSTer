project_open SNES
create_timing_netlist -model slow
read_sdc
update_timing_netlist

# Keep a general report, plus one for each clock that failed in the first pilot.
report_timing -setup -npaths 10 -nworst 1 -detail full_path \
    -file output_files/SNES.setup.rpt
foreach {signal index} {clk_mem 0 clk_sys 2} {
    set clocks [get_clocks "*emu|pll|*|counter?${index}?.output_counter|divclk"]
    if {[get_collection_size $clocks] != 1} {
        error "Could not identify a unique PLL clock for $signal"
    }
    report_timing -setup -to_clock $clocks -npaths 10 -nworst 1 -detail full_path \
        -file output_files/SNES.setup.$signal.rpt
}
delete_timing_netlist
project_close
