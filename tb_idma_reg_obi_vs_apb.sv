// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Testbench to verify OBI vs APB register block implementations
// Uses OBI interface properly with a subordinate driver

`timescale 1ns/1ps

// Include APB package first
`include "apb/src/apb_pkg.sv"

// Include APB typedefs
`include "apb/include/apb/typedef.svh"

// Include OBI typedefs
`include "obi/include/obi/typedef.svh"

// Define APB structs using the typedef macros
`APB_TYPEDEF_ALL(apb, logic [7:0], logic [31:0], logic [3:0])

package obi_tb_types_pkg;
  `OBI_TYPEDEF_MINIMAL_A_OPTIONAL(obi_a_optional_t)
  `OBI_TYPEDEF_MINIMAL_R_OPTIONAL(obi_r_optional_t)
  `OBI_TYPEDEF_TYPE_A_CHAN_T(obi_a_chan_t, logic [7:0], logic [31:0], logic [3:0], logic [0:0], obi_a_optional_t)
  `OBI_TYPEDEF_TYPE_R_CHAN_T(obi_r_chan_t, logic [31:0], logic [0:0], obi_r_optional_t)
  `OBI_TYPEDEF_REQ_T(obi_req_t, obi_a_chan_t)
  `OBI_TYPEDEF_RSP_T(obi_rsp_t, obi_r_chan_t)
endpackage

// OBI Interface Driver (Manager)
interface obi_driver
    import obi_tb_types_pkg::*;
    #(
        parameter ADDR_WIDTH = 8,
        parameter DATA_WIDTH = 32,
        parameter ID_WIDTH = 1
    ) (
        input wire clk_i,
        input wire rst_ni
    );

    // OBI interface signals (manager side)
    obi_req_t obi_req;
    obi_rsp_t obi_rsp;

    // Clocking block for synchronized access
    default clocking cb @(posedge clk_i);
        default input #1step output #1;
        output obi_req;
        input obi_rsp;
    endclocking

    // Reset task
    task automatic reset();
        cb.obi_req.req <= '0;
        cb.obi_req.a.addr <= '0;
        cb.obi_req.a.we <= '0;
        cb.obi_req.a.wdata <= '0;
        cb.obi_req.a.be <= '0;
        cb.obi_req.a.aid <= '0;
        cb.obi_req.a.a_optional <= '0;
    endtask

    // Task to perform a write transaction
    task automatic write(logic [ADDR_WIDTH-1:0] addr, logic [DATA_WIDTH-1:0] data, logic [DATA_WIDTH/8-1:0] be = '1);
        @(posedge clk_i);
        cb.obi_req.req <= 1'b1;
        cb.obi_req.a.addr <= addr;
        cb.obi_req.a.we <= 1'b1;
        cb.obi_req.a.wdata <= data;
        cb.obi_req.a.be <= be;
        cb.obi_req.a.aid <= '0;
        cb.obi_req.a.a_optional <= '0;
        
        // Wait for grant
        @(posedge clk_i);
        while (!cb.obi_rsp.gnt) @(posedge clk_i);
        
        // Clear request
        cb.obi_req.req <= 1'b0;
        
        // Wait for response
        while (!cb.obi_rsp.rvalid) @(posedge clk_i);
        
        // Check for errors
        if (cb.obi_rsp.r.err) begin
            $error("OBI write transaction failed with error");
        end
    endtask

    // Task to perform a read transaction
    task automatic read(logic [ADDR_WIDTH-1:0] addr, output logic [DATA_WIDTH-1:0] data);
        @(posedge clk_i);
        cb.obi_req.req <= 1'b1;
        cb.obi_req.a.addr <= addr;
        cb.obi_req.a.we <= 1'b0;
        cb.obi_req.a.wdata <= '0;
        cb.obi_req.a.be <= '1;
        cb.obi_req.a.aid <= '0;
        cb.obi_req.a.a_optional <= '0;
        
        // Wait for grant
        @(posedge clk_i);
        while (!cb.obi_rsp.gnt) @(posedge clk_i);
        
        // Clear request
        cb.obi_req.req <= 1'b0;
        
        // Wait for response
        while (!cb.obi_rsp.rvalid) @(posedge clk_i);
        
        // Get data
        data = cb.obi_rsp.r.rdata;
        
        // Check for errors
        if (cb.obi_rsp.r.err) begin
            $error("OBI read transaction failed with error");
        end
    endtask

endinterface

module tb_idma_reg_obi_vs_apb;
    import obi_tb_types_pkg::*;
    import obi_pkg::*;
    import idma_reg_apb_pkg::*;

    // Clock and reset
    logic clk;
    logic rst_n;

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Reset generation
    initial begin
        rst_n = 0;
        #100;
        rst_n = 1;
    end

    // OBI driver instance
    obi_driver #(
        .ADDR_WIDTH(8),
        .DATA_WIDTH(32),
        .ID_WIDTH(1)
    ) obi_drv (
        .clk_i(clk),
        .rst_ni(rst_n)
    );

    // APB interface signals for register block
    logic apb_psel;
    logic apb_penable;
    logic apb_pwrite;
    logic [2:0] apb_pprot;
    logic [7:0] apb_paddr;
    logic [31:0] apb_pwdata;
    logic [3:0] apb_pstrb;
    logic apb_pready;
    logic [31:0] apb_prdata;
    logic apb_pslverr;

    // APB structs for bridge
    apb_req_t apb_req;
    apb_resp_t apb_rsp;

    // Hardware interface signals for APB register block
    idma_reg_apb_pkg::idma_reg__in_t hwif_in_apb;
    idma_reg_apb_pkg::idma_reg__out_t hwif_out_apb;

    // Instantiate OBI to APB bridge
    obi_to_apb #(
        .ObiCfg(obi_pkg::obi_default_cfg(8, 32, 1, obi_pkg::ObiMinimalOptionalConfig)),
        .obi_req_t(obi_req_t),
        .obi_rsp_t(obi_rsp_t),
        .apb_req_t(apb_req_t),
        .apb_rsp_t(apb_resp_t),
        .DisableSameCycleRsp(1'b1)
    ) u_obi_to_apb (
        .clk_i(clk),
        .rst_ni(rst_n),
        .obi_req_i(obi_req),
        .obi_rsp_o(obi_rsp),
        .apb_req_o(apb_req),
        .apb_rsp_i(apb_rsp)
    );

    // Connect APB structs to individual signals
    assign apb_psel = apb_req.psel;
    assign apb_penable = apb_req.penable;
    assign apb_pwrite = apb_req.pwrite;
    assign apb_pprot = apb_req.pprot;
    assign apb_paddr = apb_req.paddr;
    assign apb_pwdata = apb_req.pwdata;
    assign apb_pstrb = apb_req.pstrb;

    assign apb_rsp.pready = apb_pready;
    assign apb_rsp.prdata = apb_prdata;
    assign apb_rsp.pslverr = apb_pslverr;

    // Instantiate APB register block
    idma_reg_apb u_idma_reg_apb (
        .clk(clk),
        .arst_n(rst_n),
        .s_apb_psel(apb_psel),
        .s_apb_penable(apb_penable),
        .s_apb_pwrite(apb_pwrite),
        .s_apb_pprot(apb_pprot),
        .s_apb_paddr(apb_paddr),
        .s_apb_pwdata(apb_pwdata),
        .s_apb_pstrb(apb_pstrb),
        .s_apb_pready(apb_pready),
        .s_apb_prdata(apb_prdata),
        .s_apb_pslverr(apb_pslverr),
        .hwif_in(hwif_in_apb),
        .hwif_out(hwif_out_apb)
    );

    // Test variables
    logic [31:0] test_data_read;
    logic [7:0] test_addr;
    int test_count = 0;
    int error_count = 0;

    // Test stimulus
    initial begin
        obi_drv.reset();
        // Wait for reset to complete
        wait(rst_n);
        #50;

        // Initialize hardware interface signals to zero (simplified)
        hwif_in_apb.conf.decouple_aw.next = 1'b0;
        hwif_in_apb.conf.decouple_rw.next = 1'b0;
        hwif_in_apb.conf.src_reduce_len.next = 1'b0;
        hwif_in_apb.conf.dst_reduce_len.next = 1'b0;
        hwif_in_apb.conf.src_max_llen.next = 3'b0;
        hwif_in_apb.conf.dst_max_llen.next = 3'b0;
        hwif_in_apb.conf.enable_nd.next = 1'b0;
        hwif_in_apb.conf.src_protocol.next = 3'b0;
        hwif_in_apb.conf.dst_protocol.next = 3'b0;
        
        // Initialize arrays to zero
        for (int i = 0; i < 16; i++) begin
            hwif_in_apb.status[i].rd_ack = 1'b0;
            hwif_in_apb.status[i].wr_ack = 1'b0;
            hwif_in_apb.status[i].rd_data = '{22'b0, 10'b0};
        end
        
        for (int i = 0; i < 16; i++) begin
            hwif_in_apb.next_id[i].rd_ack = 1'b0;
            hwif_in_apb.next_id[i].wr_ack = 1'b0;
            hwif_in_apb.next_id[i].rd_data = '{32'b0};
        end
        
        for (int i = 0; i < 16; i++) begin
            hwif_in_apb.done_id[i].rd_ack = 1'b0;
            hwif_in_apb.done_id[i].wr_ack = 1'b0;
            hwif_in_apb.done_id[i].rd_data = '{32'b0};
        end
        
        for (int i = 0; i < 1; i++) begin
            hwif_in_apb.dst_addr[i].dst_addr.next = 32'b0;
            hwif_in_apb.src_addr[i].src_addr.next = 32'b0;
            hwif_in_apb.length[i].length.next = 32'b0;
            hwif_in_apb.dim[i].dst_stride[0].dst_stride.next = 32'b0;
            hwif_in_apb.dim[i].src_stride[0].src_stride.next = 32'b0;
            hwif_in_apb.dim[i].reps[0].reps.next = 32'b0;
        end

        // Test 1: Write to configuration register through OBI-to-APB bridge
        test_addr = 8'h00;
        
        $display("Test %0d: Writing 0xA5A5A5A5 to address 0x%02x through OBI-to-APB bridge", test_count++, test_addr);
        
        // Write through OBI driver
        obi_drv.write(test_addr, 32'hA5A5A5A5);
        
        #20;
        
        // Read back and verify
        obi_drv.read(test_addr, test_data_read);
        $display("Read back: 0x%08x", test_data_read);
        
        if (test_data_read !== 32'hA5A5A5A5) begin
            $error("Mismatch in configuration register readback");
            error_count++;
        end
        
        // Test 2: Write to destination address register
        test_addr = 8'hD0;
        
        $display("Test %0d: Writing 0x12345678 to address 0x%02x through OBI-to-APB bridge", test_count++, test_addr);
        
        obi_drv.write(test_addr, 32'h12345678);
        
        #20;
        
        obi_drv.read(test_addr, test_data_read);
        $display("Read back: 0x%08x", test_data_read);
        
        if (test_data_read !== 32'h12345678) begin
            $error("Mismatch in destination address register readback");
            error_count++;
        end
        
        // Test 3: Write to source address register
        test_addr = 8'hD4;
        
        $display("Test %0d: Writing 0x87654321 to address 0x%02x through OBI-to-APB bridge", test_count++, test_addr);
        
        obi_drv.write(test_addr, 32'h87654321);
        
        #20;
        
        obi_drv.read(test_addr, test_data_read);
        $display("Read back: 0x%08x", test_data_read);
        
        if (test_data_read !== 32'h87654321) begin
            $error("Mismatch in source address register readback");
            error_count++;
        end
        
        // Test 4: Write to length register
        test_addr = 8'hD8;
        
        $display("Test %0d: Writing 0x00001000 to address 0x%02x through OBI-to-APB bridge", test_count++, test_addr);
        
        obi_drv.write(test_addr, 32'h00001000);
        
        #20;
        
        obi_drv.read(test_addr, test_data_read);
        $display("Read back: 0x%08x", test_data_read);
        
        if (test_data_read !== 32'h00001000) begin
            $error("Mismatch in length register readback");
            error_count++;
        end
        
        // Test 5: Test byte enables (partial write)
        test_addr = 8'h00;
        
        $display("Test %0d: Partial write to address 0x%02x (byte enables 0x3)", test_count++, test_addr);
        
        // Write only lower 2 bytes
        obi_drv.write(test_addr, 32'hDEADBEEF, 4'h3);
        
        #20;
        
        obi_drv.read(test_addr, test_data_read);
        $display("Read back after partial write: 0x%08x", test_data_read);
        
        // Expected: 0xA5A5BEEF (upper bytes unchanged, lower bytes written)
        if (test_data_read !== 32'hA5A5BEEF) begin
            $error("Mismatch in partial write test");
            error_count++;
        end
        
        // Check register outputs
        $display("Checking register outputs:");
        $display("APB conf.decouple_aw: %b", hwif_out_apb.conf.decouple_aw.value);
        $display("APB dst_addr[0].dst_addr: 0x%08x", hwif_out_apb.dst_addr[0].dst_addr.value);
        $display("APB src_addr[0].src_addr: 0x%08x", hwif_out_apb.src_addr[0].src_addr.value);
        $display("APB length[0].length: 0x%08x", hwif_out_apb.length[0].length.value);
        
        // Final results
        if (error_count == 0) begin
            $display("PASS: All tests passed successfully!");
        end else begin
            $display("FAIL: %0d errors found", error_count);
        end
        
        #100;
        $finish;
    end

    // Monitor for debugging
    always @(posedge clk) begin
        if (obi_drv.obi_req.req && obi_drv.obi_rsp.gnt) begin
            $display("OBI Request: addr=0x%02x, we=%b, wdata=0x%08x, be=0x%01x", 
                     obi_drv.obi_req.a.addr, obi_drv.obi_req.a.we, obi_drv.obi_req.a.wdata, obi_drv.obi_req.a.be);
        end
        
        if (obi_drv.obi_rsp.rvalid) begin
            $display("OBI Response: rdata=0x%08x, err=%b", obi_drv.obi_rsp.r.rdata, obi_drv.obi_rsp.r.err);
        end
        
        if (apb_psel && apb_penable) begin
            $display("APB Request: addr=0x%02x, write=%b, wdata=0x%08x, strb=0x%01x", 
                     apb_paddr, apb_pwrite, apb_pwdata, apb_pstrb);
        end
        
        if (apb_pready) begin
            $display("APB Response: rdata=0x%08x, slverr=%b", apb_prdata, apb_pslverr);
        end
    end

endmodule
