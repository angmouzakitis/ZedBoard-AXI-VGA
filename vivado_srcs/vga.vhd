library ieee;                                                                             
use ieee.std_logic_1164.all;                                                              
use ieee.numeric_std.all;                                                                                                 

entity vga is port (                                                                                                   
    M_AXI_ACLK      : in std_logic;                                                                                       
    M_AXI_ARESETN   : in std_logic;                                                                                                           
    M_AXI_ARADDR    : out std_logic_vector(31 downto 0);
    M_AXI_ARLEN     : out std_logic_vector(7 downto 0);
    M_AXI_ARSIZE    : out std_logic_vector(2 downto 0); 
    M_AXI_ARBURST   : out std_logic_vector(1 downto 0);
    M_AXI_ARPROT    : out std_logic_vector(2 downto 0);
    M_AXI_ARVALID   : out std_logic;
    M_AXI_ARREADY   : in  std_logic;
    M_AXI_RDATA     : in  std_logic_vector(31 downto 0);
    M_AXI_RLAST     : in  std_logic;
    M_AXI_RVALID    : in  std_logic;
    M_AXI_RREADY    : out std_logic;
    r               : out std_logic_vector(3 downto 0);
    g               : out std_logic_vector(3 downto 0);
    b               : out std_logic_vector(3 downto 0);
    hs              : out std_logic;
    vs              : out std_logic
);
end vga;

architecture impl of vga is

type axi_master_fsm is (REQUEST_READ, ADDRESS_READY, READ, IDLE);
signal state : axi_master_fsm   := REQUEST_READ;
type slave_registers is array (0 to 3) of std_logic_vector(31 downto 0);
signal reg   : slave_registers := (others => (x"0100_0000"));

signal arvalid          : std_logic := '0';
signal rready           : std_logic := '0';
signal next_address     : unsigned(31 downto 0) := x"0100_0000";

constant ZERO             : unsigned(10 downto 0) := (others => '0');
constant h_active         : unsigned(10 downto 0) := ZERO + 640;
constant h_front_porch    : unsigned(10 downto 0) := h_active        + 16;
constant h_sync_pulse     : unsigned(10 downto 0) := h_front_porch   + 96;
constant h_back_porch     : unsigned(10 downto 0) := h_sync_pulse    + 48 -1; 
constant v_active         : unsigned(10 downto 0) := ZERO + 480;
constant v_front_porch    : unsigned(10 downto 0) := v_active        + 10;
constant v_sync_pulse     : unsigned(10 downto 0) := v_front_porch   + 2;
constant v_back_porch     : unsigned(10 downto 0) := v_sync_pulse    + 33 - 1;

type pixel_buffer_type is array (0 to 63) of std_logic_vector(31 downto 0);
signal pixel_buffer       : pixel_buffer_type;
signal pixel_cnt          : unsigned(5  downto 0) := (others => '0');
signal clk_divider        : unsigned(1  downto 0) := (others => '0');
signal h_cnt              : unsigned(10 downto 0) := (others => '0');
signal v_cnt              : unsigned(10 downto 0) := (others => '0');

begin 

M_AXI_ARSIZE  <= "010"; -- 4 bytes per transfer
M_AXI_ARBURST <= "01";  -- INCR burst type
M_AXI_ARLEN   <= x"1f"; -- 32 fetches
M_AXI_ARVALID <= arvalid;
M_AXI_ARPROT  <= (others => '0');
M_AXI_RREADY  <= rready;

axi_read_fsm : process(M_AXI_ACLK)
begin
    if rising_edge(M_AXI_ACLK) then
        case state is
            when REQUEST_READ =>
                pixel_cnt <= (others => '0');
                arvalid <= '1';
                M_AXI_ARADDR <= std_logic_vector(next_address);
                state <= ADDRESS_READY;
            when ADDRESS_READY =>
                if M_AXI_ARREADY = '1' then
                    arvalid <= '0';
                    rready <= '1';
                    state <= READ; 
                end if;
            when READ => 
                if M_AXI_RVALID = '1' then
                    pixel_buffer(to_integer(pixel_cnt)) <= M_AXI_RDATA;
                    pixel_cnt <= pixel_cnt + 1;
                    if M_AXI_RLAST = '1' then
                        state <= IDLE;
                    end if;
                end if;
             when IDLE =>
                if h_cnt(5 downto 0) = 53 then
                    if h_cnt < h_active then
                        next_address <= next_address + 128;
                    elsif v_cnt > v_active then
                        next_address <= unsigned(reg(0));
                    end if;
                        state <= REQUEST_READ;
                end if;
        end case;
    end if;
end process;

vga_clocking: process (M_AXI_ACLK)
begin
    if rising_edge(M_AXI_ACLK) then
        clk_divider <= clk_divider + 1;
        if clk_divider = 4 - 1 then -- 102Mhz ACLK input clock required
            clk_divider <= (others => '0');
            if h_cnt(0) = '0' then
                r <= pixel_buffer(to_integer("0" & (h_cnt(5 downto 1))))(11 downto 8);
                g <= pixel_buffer(to_integer("0" & (h_cnt(5 downto 1))))(7  downto 4);
                b <= pixel_buffer(to_integer("0" & (h_cnt(5 downto 1))))(3  downto 0);
            else
                r <= pixel_buffer(to_integer((h_cnt(5 downto 0) - 1) / 2))(27 downto 24);
                g <= pixel_buffer(to_integer((h_cnt(5 downto 0) - 1) / 2))(23 downto 20);
                b <= pixel_buffer(to_integer((h_cnt(5 downto 0) - 1) / 2))(19 downto 16);
            end if;
            if v_cnt >= v_active or h_cnt >= h_active then 
                r <= (others => '0');
                g <= (others => '0');
                b <= (others => '0');
            end if;
            h_cnt <= h_cnt + 1;
            if h_cnt = h_back_porch then
                h_cnt <= (others => '0');
                v_cnt <= v_cnt + 1;
                if v_cnt = v_back_porch then
                    v_cnt <= (others => '0');
                end if;
            end if;
        end if;
    end if;
end process;

vs <= '1' when v_cnt >= v_front_porch and v_cnt <= v_sync_pulse else '0';
hs <= '1' when h_cnt >= h_front_porch and h_cnt <= h_sync_pulse else '0';

end impl;
