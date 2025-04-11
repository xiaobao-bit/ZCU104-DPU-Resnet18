# auto_generate_bitstream.tcl
# This script automates HDL wrapper creation, block design generation, bitstream generation,
# and XSA export for a design named "system" in Vivado 2022.2

set design_name "system"

# Step 1: Create HDL wrapper (Let Vivado manage it)
puts "Creating HDL wrapper..."
make_wrapper -files [get_files ${design_name}.bd] -top -import

# Step 2: Generate block design (pre-synth)
puts "Generating block design..."
generate_target all [get_files ${design_name}.bd]

# Step 3: Set implementation strategy
puts "Setting implementation strategy..."
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]

# Step 4: Launch synthesis and implementation
puts "Launching synthesis and implementation..."
launch_runs synth_1 -jobs 2
wait_on_run synth_1

launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1

# Step 5: Generate bitstream
puts "Generating bitstream..."
if {[catch {write_bitstream} err]} {
    puts "Bitstream generation may already be done or manually triggered."
} else {
    puts "Bitstream generation triggered manually."
}

# Step 6: Export hardware with bitstream
puts "Exporting hardware with bitstream..."
write_hw_platform -fixed -include_bit -force -file "${design_name}.xsa"

puts "Done! Exported ${design_name}.xsa"

