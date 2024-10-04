test:
	iverilog -DSIM -DmySIM -o project tokenflow.v
	./project

lint:
	verilator --lint-only --timing --top-module tt_um_tommythorn_maxbw project.v tokenflow.v
