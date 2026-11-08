# =======================================================================
# |                        Test Description                             |
# =======================================================================
# This test sets up the PRC with 1 Virtual Socket (vs_shift) and 2 RMs.
# Adapted for AX7325 (myb) board with SPI Flash interface.
#

# "Shift" Virtual Socket (ID 0)
# -----------------------------

set rm_shift_left_address  0xAEA000
set rm_shift_left_size       215280

set rm_shift_right_address 0xB60000
set rm_shift_right_size      215280
