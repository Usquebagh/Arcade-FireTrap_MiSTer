derive_pll_clocks
derive_clock_uncertainty

# core specific constraints

# The 8751 (jt8051 + its ROM/RAM in ft_mcu) only advances on an 8 MHz enable (every 6 clocks);
# jt8051 is designed for a two-cycle budget (rtl/jt8051/README.md, syn/timing.sdc upstream).
set_multicycle_path -from {*|ft_mcu:u_mcu|*} -to {*|ft_mcu:u_mcu|*} -setup -end 2
set_multicycle_path -from {*|ft_mcu:u_mcu|*} -to {*|ft_mcu:u_mcu|*} -hold  -end 1
