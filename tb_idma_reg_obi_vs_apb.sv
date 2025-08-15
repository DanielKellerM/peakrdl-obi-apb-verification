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
    import idma_reg_obi_pkg::*;

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
    ) obi_drv_apb (
        .clk_i(clk),
        .rst_ni(rst_n)
    );

    // Define APB structs using the typedef macros
    `APB_TYPEDEF_ALL(apb, logic [7:0], logic [31:0], logic [3:0])

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
    idma_reg_obi_pkg::idma_reg__in_t  hwif_in_obi;
    idma_reg_obi_pkg::idma_reg__out_t hwif_out_obi;

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
        .obi_req_i(obi_drv_apb.obi_req),
        .obi_rsp_o(obi_drv_apb.obi_rsp),
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
    logic [31:0] conf_mask;
    logic [31:0] expected_conf;

    always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (int i = 0; i < 16; i++) begin
        hwif_in_apb.status[i].rd_ack <= 1'b0;
        hwif_in_apb.status[i].wr_ack <= 1'b0;
        // provide some status data
        hwif_in_apb.status[i].rd_data <= '{default:'0};
        hwif_in_apb.next_id[i].rd_ack <= 1'b0;
        hwif_in_apb.next_id[i].wr_ack <= 1'b0;
        hwif_in_apb.next_id[i].rd_data<= '{default:'0};
        hwif_in_apb.done_id[i].rd_ack <= 1'b0;
        hwif_in_apb.done_id[i].wr_ack <= 1'b0;
        hwif_in_apb.done_id[i].rd_data<= '{default:'0};
        end
    end else begin
        for (int i = 0; i < 16; i++) begin
        // READ handshake
        if (hwif_out_apb.status[i].req && !hwif_out_apb.status[i].req_is_wr) begin
            hwif_in_apb.status[i].rd_ack  <= 1'b1;           // 1-cycle pulse
            hwif_in_apb.status[i].rd_data <= '{default:'0};  // your value
        end else begin
            hwif_in_apb.status[i].rd_ack  <= 1'b0;
        end

        // WRITE handshake (ack write data)
        if (hwif_out_apb.status[i].req && hwif_out_apb.status[i].req_is_wr) begin
            // consume hwif_out_apb.status[i].wr_data here if that field supports writes
            hwif_in_apb.status[i].wr_ack <= 1'b1;
        end else begin
            hwif_in_apb.status[i].wr_ack <= 1'b0;
        end

        if (hwif_out_apb.next_id[i].req && !hwif_out_apb.next_id[i].req_is_wr) begin
            hwif_in_apb.next_id[i].rd_ack <= 1'b1;
            hwif_in_apb.next_id[i].rd_data <= '{default:'0};
        end else begin
            hwif_in_apb.next_id[i].rd_ack <= 1'b0;
        end

        if (hwif_out_apb.done_id[i].req && !hwif_out_apb.done_id[i].req_is_wr) begin
            hwif_in_apb.done_id[i].rd_ack <= 1'b1;
            hwif_in_apb.done_id[i].rd_data <= '{default:'0};
        end else begin
            hwif_in_apb.done_id[i].rd_ack <= 1'b0;
        end
        end
    end
    end

    // Hold-behavior loopback: drive all .next from .value
    // CONF
    assign hwif_in_apb.conf.decouple_aw.next   = hwif_out_apb.conf.decouple_aw.value;
    assign hwif_in_apb.conf.decouple_rw.next   = hwif_out_apb.conf.decouple_rw.value;
    assign hwif_in_apb.conf.src_reduce_len.next= hwif_out_apb.conf.src_reduce_len.value;
    assign hwif_in_apb.conf.dst_reduce_len.next= hwif_out_apb.conf.dst_reduce_len.value;
    assign hwif_in_apb.conf.src_max_llen.next  = hwif_out_apb.conf.src_max_llen.value;
    assign hwif_in_apb.conf.dst_max_llen.next  = hwif_out_apb.conf.dst_max_llen.value;
    assign hwif_in_apb.conf.enable_nd.next     = hwif_out_apb.conf.enable_nd.value;
    assign hwif_in_apb.conf.src_protocol.next  = hwif_out_apb.conf.src_protocol.value;
    assign hwif_in_apb.conf.dst_protocol.next  = hwif_out_apb.conf.dst_protocol.value;

    // SCALAR REGS
    assign hwif_in_apb.dst_addr[0].dst_addr.next = hwif_out_apb.dst_addr[0].dst_addr.value;
    assign hwif_in_apb.src_addr[0].src_addr.next = hwif_out_apb.src_addr[0].src_addr.value;
    assign hwif_in_apb.length [0].length .next   = hwif_out_apb.length [0].length .value;

    // DIM REGS
    assign hwif_in_apb.dim[0].dst_stride[0].dst_stride.next = hwif_out_apb.dim[0].dst_stride[0].dst_stride.value;
    assign hwif_in_apb.dim[0].src_stride[0].src_stride.next = hwif_out_apb.dim[0].src_stride[0].src_stride.value;
    assign hwif_in_apb.dim[0].reps      [0].reps      .next = hwif_out_apb.dim[0].reps      [0].reps      .value;

    // OBI
    // Second driver
    obi_driver #(
        .ADDR_WIDTH(8),
        .DATA_WIDTH(32),
        .ID_WIDTH(1)
        ) obi_drv_obi (
        .clk_i(clk),
        .rst_ni(rst_n)
    );
    logic        obi_req_f;
    logic [7:0]  obi_addr_f;
    logic        obi_we_f;
    logic [3:0]  obi_be_f;
    logic [31:0] obi_wdata_f;
    logic [0:0]  obi_aid_f;
    logic        obi_gnt_f;
    logic        obi_rvalid_f;
    logic [31:0] obi_rdata_f;
    logic [0:0]  obi_rid_f;
    logic        obi_err_f;
    logic        obi_rready_f;

    // Always ready (your bridge/DUT doesn’t use RReady)
    assign obi_rready_f = 1'b1;

    // Struct -> flat wiring into idma_reg_obi
    assign obi_req_f    = obi_drv_obi.obi_req.req;
    assign obi_addr_f   = obi_drv_obi.obi_req.a.addr;
    assign obi_we_f     = obi_drv_obi.obi_req.a.we;
    assign obi_wdata_f  = obi_drv_obi.obi_req.a.wdata;
    assign obi_be_f     = obi_drv_obi.obi_req.a.be;
    assign obi_aid_f    = obi_drv_obi.obi_req.a.aid;

    assign obi_drv_obi.obi_rsp.gnt        = obi_gnt_f;
    assign obi_drv_obi.obi_rsp.rvalid     = obi_rvalid_f;
    assign obi_drv_obi.obi_rsp.r.rdata    = obi_rdata_f;
    assign obi_drv_obi.obi_rsp.r.rid      = obi_rid_f;
    assign obi_drv_obi.obi_rsp.r.err      = obi_err_f;
    // No optional R fields; zero them
    assign obi_drv_obi.obi_rsp.r.r_optional = '0;

    assign hwif_in_obi.conf.decouple_aw.next    = hwif_out_obi.conf.decouple_aw.value;
    assign hwif_in_obi.conf.decouple_rw.next    = hwif_out_obi.conf.decouple_rw.value;
    assign hwif_in_obi.conf.src_reduce_len.next = hwif_out_obi.conf.src_reduce_len.value;
    assign hwif_in_obi.conf.dst_reduce_len.next = hwif_out_obi.conf.dst_reduce_len.value;
    assign hwif_in_obi.conf.src_max_llen.next   = hwif_out_obi.conf.src_max_llen.value;
    assign hwif_in_obi.conf.dst_max_llen.next   = hwif_out_obi.conf.dst_max_llen.value;
    assign hwif_in_obi.conf.enable_nd.next      = hwif_out_obi.conf.enable_nd.value;
    assign hwif_in_obi.conf.src_protocol.next   = hwif_out_obi.conf.src_protocol.value;
    assign hwif_in_obi.conf.dst_protocol.next   = hwif_out_obi.conf.dst_protocol.value;

    assign hwif_in_obi.dst_addr[0].dst_addr.next = hwif_out_obi.dst_addr[0].dst_addr.value;
    assign hwif_in_obi.src_addr[0].src_addr.next = hwif_out_obi.src_addr[0].src_addr.value;
    assign hwif_in_obi.length [0].length .next   = hwif_out_obi.length [0].length .value;

    assign hwif_in_obi.dim[0].dst_stride[0].dst_stride.next = hwif_out_obi.dim[0].dst_stride[0].dst_stride.value;
    assign hwif_in_obi.dim[0].src_stride[0].src_stride.next = hwif_out_obi.dim[0].src_stride[0].src_stride.value;
    assign hwif_in_obi.dim[0].reps      [0].reps      .next = hwif_out_obi.dim[0].reps      [0].reps      .value;

    // External arrays: acks low unless responding to req (same pattern as *_apb)
    always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (int i=0;i<16;i++) begin
        hwif_in_obi.status [i].rd_ack <= 1'b0; hwif_in_obi.status [i].wr_ack <= 1'b0;
        hwif_in_obi.next_id[i].rd_ack <= 1'b0; hwif_in_obi.next_id[i].wr_ack <= 1'b0;
        hwif_in_obi.done_id[i].rd_ack <= 1'b0; hwif_in_obi.done_id[i].wr_ack <= 1'b0;
        hwif_in_obi.status [i].rd_data <= '{default:'0};
        hwif_in_obi.next_id[i].rd_data <= '{default:'0};
        hwif_in_obi.done_id[i].rd_data <= '{default:'0};
        end
    end else begin
        for (int i=0;i<16;i++) begin
        hwif_in_obi.status [i].rd_ack <= hwif_out_obi.status [i].req & ~hwif_out_obi.status [i].req_is_wr;
        hwif_in_obi.status [i].wr_ack <= hwif_out_obi.status [i].req &  hwif_out_obi.status [i].req_is_wr;

        hwif_in_obi.next_id[i].rd_ack <= hwif_out_obi.next_id[i].req & ~hwif_out_obi.next_id[i].req_is_wr;
        hwif_in_obi.next_id[i].wr_ack <= hwif_out_obi.next_id[i].req &  hwif_out_obi.next_id[i].req_is_wr;

        hwif_in_obi.done_id[i].rd_ack <= hwif_out_obi.done_id[i].req & ~hwif_out_obi.done_id[i].req_is_wr;
        hwif_in_obi.done_id[i].wr_ack <= hwif_out_obi.done_id[i].req &  hwif_out_obi.done_id[i].req_is_wr;
        end
    end
    end

    // Flattened OBI wires for the custom regblock

    idma_reg_obi u_idma_reg_obi (
        .clk(clk),
        .arst_n(rst_n),
        .obi_req(obi_req_f),
        .obi_addr(obi_addr_f),
        .obi_we(obi_we_f),
        .obi_be(obi_be_f),
        .obi_wdata(obi_wdata_f),
        .obi_aid(obi_aid_f),
        .obi_gnt(obi_gnt_f),
        .obi_rvalid(obi_rvalid_f),
        .obi_rdata(obi_rdata_f),
        .obi_rid(obi_rid_f),
        .obi_err(obi_err_f),
        .obi_rready(obi_rready_f),
        .hwif_in(hwif_in_obi),
        .hwif_out(hwif_out_obi)
    );

    // Test stimulus
    task automatic write_both (logic [7:0] addr, logic [31:0] data, logic [3:0] be=4'hF);
        // APB path (via obi_to_apb)
        obi_drv_apb.write(addr, data, be);
        // OBI native path
        obi_drv_obi.write(addr, data, be);
    endtask

    task automatic read_both_and_compare (logic [7:0] addr, logic [31:0] mask=32'hFFFF_FFFF);
        logic [31:0] rd_apb, rd_obi;
        obi_drv_apb.read(addr, rd_apb);
        obi_drv_obi.read(addr, rd_obi);
        if ( (rd_apb & mask) !== (rd_obi & mask) ) begin
            $error("Mismatch @0x%02h  APB:%08h  OBI:%08h (mask:%08h)", addr, rd_apb, rd_obi, mask);
            error_count++;
        end
    endtask

    initial begin
        obi_drv_apb.reset();
        obi_drv_obi.reset();
        // Wait for reset to complete
        wait(rst_n);
        #50;

        // Test 1: Write to configuration register through OBI-to-APB bridge
        test_addr = 8'h00;  // Configuration register at word address 0x00
        $display("Test %0d: Writing 0xA5A5A5A5 to address 0x%02x through OBI-to-APB bridge", test_count++, test_addr);
        write_both(test_addr, 32'hA5A5A5A5);
        #20;
        read_both_and_compare(test_addr, 32'h0001_FFFF);

        // Test 2: Write to destination address register
        test_addr = 8'hD0;
        $display("Test %0d: Writing 0x12345678 to address 0x%02x through OBI-to-APB bridge", test_count++, test_addr);
        write_both(test_addr, 32'h12345678);
        #20;
        read_both_and_compare(test_addr);

        // Test 3: Write to source address register
        test_addr = 8'hD4;
        $display("Test %0d: Writing 0x87654321 to address 0x%02x through OBI-to-APB bridge", test_count++, test_addr);
        write_both(test_addr, 32'h87654321);
        #20;
        read_both_and_compare(test_addr);

        // Test 4: Write to length register
        test_addr = 8'hD8;
        $display("Test %0d: Writing 0x00001000 to address 0x%02x through OBI-to-APB bridge", test_count++, test_addr);
        write_both(test_addr, 32'h00001000);
        #20;
        read_both_and_compare(test_addr);

        // Test 5: Test byte enables (partial write)
        test_addr = 8'h00;  // Back to configuration register
        $display("Test %0d: Partial write to address 0x%02x (byte enables 0x3)", test_count++, test_addr);
        write_both(test_addr, 32'hDEADBEEF, 4'h3);
        #20;
        read_both_and_compare(test_addr, 32'h0001_FFFF);

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
        if (obi_drv_apb.obi_req.req && obi_drv_apb.obi_rsp.gnt) begin
            $display("OBI Request: addr=0x%02x, we=%b, wdata=0x%08x, be=0x%01x", 
                     obi_drv_apb.obi_req.a.addr, obi_drv_apb.obi_req.a.we, obi_drv_apb.obi_req.a.wdata, obi_drv_apb.obi_req.a.be);
        end
        if (obi_drv_obi.obi_req.req && obi_drv_obi.obi_rsp.gnt) begin
            $display("OBI Request: addr=0x%02x, we=%b, wdata=0x%08x, be=0x%01x", 
                     obi_drv_obi.obi_req.a.addr, obi_drv_obi.obi_req.a.we, obi_drv_obi.obi_req.a.wdata, obi_drv_obi.obi_req.a.be);
        end

        if (obi_drv_apb.obi_rsp.rvalid) begin
            $display("OBI Response: rdata=0x%08x, err=%b", obi_drv_apb.obi_rsp.r.rdata, obi_drv_apb.obi_rsp.r.err);
        end

        if (obi_drv_obi.obi_rsp.rvalid) begin
            $display("OBI Response: rdata=0x%08x, err=%b", obi_drv_obi.obi_rsp.r.rdata, obi_drv_obi.obi_rsp.r.err);
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
