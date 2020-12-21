library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity io_ps2_out is
port (
  CLK          : in std_logic;
  OSD_ENA      : in std_logic;
  --KEY_VIDEO  : out std_logic;
  ps2_int      : in std_logic;
  ps2_code     : in std_logic_vector(7 downto 0);
  ps2_key      : buffer std_logic_vector(10 downto 0)
);
end io_ps2_out;

architecture ps2_out of io_ps2_out is

signal RELEASED : std_logic;
signal EXTENDED : std_logic;

begin 

process(Clk)
begin
  if rising_edge(Clk) then
    if ps2_int = '1' and OSD_ENA = '0' then 
			if ps2_code = "11110000" then RELEASED <= '1'; else RELEASED <= '0'; end if; 
			if ps2_code = x"e0" 	    then EXTENDED <= '1'; else EXTENDED <= '0'; end if;
			--de mist_io-- ps2_key <= {~ps2_key[10], pressed, extended, ps2_key_raw[7:0]};
			-- 10 = fluctua cada pulsacion, 9 - pulsado, 8 - extendendido, [7:0] codigo ps2
			ps2_key <= '1' & not RELEASED & EXTENDED & ps2_code;
			--if ps2_code = x"7e" and RELEASED = '1' then KEY_VIDEO <= not KEY_VIDEO; end if; --BLoq Despl						
	 else
			ps2_key <= (others => '0');
	 end if;
  end if;
end process;

end ps2_out;


