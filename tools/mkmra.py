#!/usr/bin/env python3
"""Generate the MRA files (releases/*.mra) for firetrap, firetrapa and firetrapj.
Part order = the core's download layout (docs/hardware.md, rtl/ft_core.v)."""
import os

US_GFX = [
    # BG1 (download order di-06, di-04, di-07, di-05)
    ("di-06.3e", "441d9154"), ("di-04.2e", "8e6e7eec"), ("di-07.6e", "ef0a7e23"), ("di-05.4e", "ec080082"),
    # BG2
    ("di-09.3j", "d11e28e8"), ("di-08.2j", "c32a21d8"), ("di-11.6j", "6424d5c3"), ("di-10.4j", "9b89300a"),
    # sprites, one bit plane per chip
    ("di-16.17h", "0de055d7"), ("di-13.13h", "869219da"), ("di-14.14h", "6b65812e"), ("di-15.15h", "3e27f77d"),
]
JP_GFX = [
    ("fi-06.3e", "441d9154"), ("fi-05.2e", "8e6e7eec"), ("fi-08.6e", "ef0a7e23"), ("fi-07.4e", "ec080082"),
    ("fi-10.3j", "d11e28e8"), ("fi-09.2j", "c32a21d8"), ("fi-12.6j", "6424d5c3"), ("fi-11.4j", "9b89300a"),
    ("fi-17.17h", "0de055d7"), ("fi-14.13h", "dbcdd3df"), ("fi-15.14h", "6b65812e"), ("fi-16.15h", "3e27f77d"),
]
US_PROM = [("firetrap.3b", "8bb45337"), ("firetrap.4b", "d5abfc64"), ("firetrap.1a", "d67f3514")]
JP_PROM = [("fi-2.3b", "8bb45337"), ("fi-3.4b", "d5abfc64"), ("fi-1.1a", "d67f3514")]

SETS = [
    ("Fire Trap (US, rev A)", "firetrap", "firetrap", "US", "firetrap.zip",
     [("di-02.4a", "3d1e4bf7"), ("di-01.3a", "9bbae38b"), ("di-00-a.2a", "f39e2cf4")],
     [("di-17.10j", "8605f6b9"), ("di-18.12j", "49508c93")], ("di-12.16h", "6340a4d7"),
     ("di-03.17c", "46721930"), US_PROM, US_GFX),
    ("Fire Trap (US)", "firetrapa", "firetrap", "US", "firetrapa.zip|firetrap.zip",
     [("di-02.4a", "3d1e4bf7"), ("di-01.3a", "9bbae38b"), ("di-00.2a", "d0dad7de")],
     [("di-17.10j", "8605f6b9"), ("di-18.12j", "49508c93")], ("di-12.16h", "6340a4d7"),
     ("di-03.17c", "46721930"), US_PROM, US_GFX),
    ("Fire Trap (Japan)", "firetrapj", "firetrap", "Japan", "firetrapj.zip|firetrap.zip",
     [("fi-03.4a", "20b2a4ff"), ("fi-02.3a", "5c8a0562"), ("fi-01.2a", "f2412fe8")],
     [("fi-18.10j", "8605f6b9"), ("fi-19.12j", "49508c93")], ("fi-13.16h", "e531a633"),
     ("fi-04.17c", "a584fc16"), JP_PROM, JP_GFX),
]

BONUS_US = ('ids="50k and 100k,30k and 70k,50k only,30k only"', 'values="0,1,2,3"')
BONUS_JP = ('ids="50k only,80k and every 100k,60k and every 80k,50k and every 70k"', 'values="0,1,2,3"')

def parts(lst, indent="\t\t"):
    return "\n".join(f'{indent}<part crc="{c}" name="{n}"/>' for n, c in lst)

for title, setname, parent, region, zips, main, snd, mcu, chars, proms, gfx in SETS:
    bonus = BONUS_JP if region == "Japan" else BONUS_US
    mra = f"""<misterromdescription>
	<name>{title}</name>
	<region>{region}</region>
	<homebrew>no</homebrew>
	<bootleg>no</bootleg>
	<version></version>
	<alternative></alternative>
	<platform>Data East</platform>
	<series></series>
	<year>1986</year>
	<manufacturer>{"Wood Place" if region == "Japan" else "Wood Place (Data East USA license)"}</manufacturer>
	<category>Climbing</category>

	<setname>{setname}</setname>
	<parent>{parent}</parent>
	<mameversion>0289</mameversion>
	<rbf>FireTrap</rbf>
	<about author="Usquebagh" webpage="https://github.com/Usquebagh/Arcade-FireTrap_MiSTer">Fire Trap (1986): Z80, i8751 MCU, 6502, YM3526, MSM5205.</about>

	<rotation>vertical (cw)</rotation>
	<flip>yes</flip>

	<players>2 (alternating)</players>
	<joystick>4-way</joystick>
	<special_controls>dual joystick</special_controls>
	<num_buttons>1</num_buttons>
	<buttons default="R,X,B,Y,A,Start,Select" names="Fire,R-Stick Up,R-Stick Down,R-Stick Left,R-Stick Right,Start,Coin"/>

	<switches default="DF,FF">
		<dip bits="0,2" name="Coin A" ids="1C/6C,1C/4C,1C/3C,1C/2C,1C/1C" values="4,3,5,6,7"/>
		<dip bits="3,4" name="Coin B" ids="4C/1C,3C/1C,2C/1C,1C/1C" values="0,1,2,3"/>
		<dip bits="5" name="Cabinet" ids="Upright,Cocktail"/>
		<dip bits="6" name="Demo Sounds" ids="Off,On"/>
		<dip bits="7" name="Flip Screen" ids="On,Off"/>
		<dip bits="8,9" name="Difficulty" ids="Hardest,Hard,Easy,Normal" values="0,1,2,3"/>
		<dip bits="10,11" name="Lives" ids="2,5,4,3" values="0,1,2,3"/>
		<dip bits="12,13" name="Bonus Life" {bonus[0]} {bonus[1]}/>
		<dip bits="14" name="Allow Continue" ids="No,Yes"/>
		<dip bits="15" name="Service Mode" ids="On,Off"/>
	</switches>

	<!-- Layout must match the download decode in rtl/ft_core.v -->
	<rom index="0" md5="none" zip="{zips}">
		<!-- 00000 main CPU: 0000-7FFF, then banks 0-3 -->
{parts(main)}
		<!-- 18000 sound CPU: 8000-FFFF, then banks 0-1 -->
{parts(snd)}
		<!-- 28000 i8751 -->
{parts([mcu])}
		<!-- 29000 FG characters -->
{parts([chars])}
		<!-- 2B000 palette PROMs (R/G, B) and priority PROM -->
{parts(proms)}
		<part repeat="0xD00">FF</part>
		<!-- 2C000 BG1, 4C000 BG2, 6C000 sprites (to SDRAM) -->
{parts(gfx)}
	</rom>

	<!-- Cheats converted from the MAME cheat file (https://www.mamecheat.co.uk; same addresses
	     in all sets). Format: flags(4) address(4) compare(4) value(4); applied to Z80 reads. -->
	<cheats>
		<cheat name="P1 Infinite Lives">000000 10 0000C143 00000000 00000008</cheat>
		<cheat name="P1 Infinite Time">000000 10 0000C149 00000000 0000009A</cheat>
		<cheat name="P2 Infinite Lives">000000 10 0000C151 00000000 00000008</cheat>
		<cheat name="P2 Infinite Time">000000 10 0000C157 00000000 0000009A</cheat>
		<cheat name="3-Way Powerup">000000 10 0000C145 00000000 00000002</cheat>
	</cheats>
</misterromdescription>
"""
    os.makedirs("releases", exist_ok=True)
    open(f"releases/{title}.mra", "w", newline="\n").write(mra)
    print("wrote", title)
