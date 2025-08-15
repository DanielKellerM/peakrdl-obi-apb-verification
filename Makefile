# Makefile for OBI Interface Testbench

# Compiler settings
VLOG = vlog
VSIM = vsim
VOPT = vopt

# Source files for OBI vs APB comparison test
SOURCES = common_cells/src/cf_math_pkg.sv \
		apb/src/apb_pkg.sv \
		apb/include/apb/typedef.svh \
		obi/include/obi/typedef.svh \
		obi/src/obi_pkg.sv \
		obi/src/obi_intf.sv \
		regblock/idma_reg_obi_pkg.sv \
		regblock/idma_reg_obi.sv \
		regblock/idma_reg_apb_pkg.sv \
		regblock/idma_reg_apb.sv \
		obi_to_apb.sv \
		tb_idma_reg_obi_vs_apb.sv

# Testbench modules
TB_MODULE_OBI_VS_APB = tb_idma_reg_obi_vs_apb

# Generate register blocks (if not already generated)
generate-regblocks:
	@echo "Generating register blocks..."
	@if command -v peakrdl >/dev/null 2>&1; then \
		peakrdl regblock idma_reg.rdl --module-name idma_reg_obi -o regblock/ --default-reset arst_n --cpuif obi-flat; \
		peakrdl regblock idma_reg.rdl --module-name idma_reg_apb -o regblock/ --default-reset arst_n --cpuif apb4-flat; \
	else \
		echo "Warning: peakrdl not found. Please ensure register blocks are already generated."; \
	fi

# Compile all sources for OBI vs APB test
compile: generate-regblocks
	rm -rf work
	$(VLOG) -sv -suppress 12003 $(SOURCES)

# Run simulation
sim: compile
	$(VSIM) -c -do "run -all; quit" $(TB_MODULE_OBI_VS_APB)

# Run simulation with GUI
sim-gui: compile
	$(VSIM) -gui $(TB_MODULE_OBI_VS_APB)

# Run all tests
test-all: sim sim-obi-vs-apb

# Clean generated files
clean:
	rm -rf work
	rm -rf transcript
	rm -rf vsim.wlf
	rm -rf *.log

.PHONY: compile compile-obi-vs-apb sim sim-obi-vs-apb sim-gui sim-obi-vs-apb-gui test-all help clean