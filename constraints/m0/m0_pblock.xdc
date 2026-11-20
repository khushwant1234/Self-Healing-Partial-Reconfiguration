# M0 reconfigurable partition floorplan.
#
# Slice-only range, full height of clock-region row Y2 (rows 100..149) on the
# right-hand side of the XC7Z020, away from the PS. Deliberately oversized
# for a 32-bit register (~1000 slices for ~40 FFs) -- M0 tests the flow, not
# the floorplan. RESET_AFTER_RECONFIG is left off for M0; it is turned on from
# M2 onward, where the pblocks are designed around it.
create_pblock pblock_rp
add_cells_to_pblock [get_pblocks pblock_rp] [get_cells u_rp]
resize_pblock [get_pblocks pblock_rp] -add {SLICE_X82Y100:SLICE_X101Y149}
set_property SNAPPING_MODE ON [get_pblocks pblock_rp]
