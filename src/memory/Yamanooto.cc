#include "Yamanooto.hh"

#include "DummyAY8910Periphery.hh"
#include "MSXCPUInterface.hh"
#include "MSXException.hh"

#include "narrow.hh"
#include "outer.hh"
#include "ranges.hh"
#include "unreachable.hh"

#include <cassert>
#include <ranges>

// TODO:
// * HOME/DEL boot keys.  How are these handled?
// * SCC stereo mode.
//
// FERPECT (26-11-2026): brought up to date with the "Yamanooto Hardware
// Reference" of 5-dec-2025:
// * CFGR bit 2 is now ASCII (ASCII8, or ASCII16 together with K4); the old
//   ROMDIS function is gone (the hidden bit is cleared by the firmware).
// * Writing OFFR clears the SUBOFF bits.
// * ENAR bit 5 (LOFF): the offset counts in 2MB steps, for flash chips of
//   more than 8MB. ENAR bit 2 (MSTEN) gives access to MOFFR (master offset,
//   write only) and ENAR bit 1 (SPIEN) to SPICON, both at 7FFEh.
// * SPI: SDAT (7FFCh) talks to the SD card when SPICON selects it.
// * The flash chip follows the size of the ROM image (or <flash> in the
//   config): 8MB S29GL064N, or 16/32/64/128MB S29GL128P/256P/512P/01GP.
// Not known (assumed here): the master offset uses the same step as OFFR,
// and writes to 7FFCh-7FFFh don't reach the ASCII mapper.

namespace openmsx {

static constexpr uint16_t ENAR = 0x7FFF;
static constexpr uint8_t  REGEN  = 0x01;
static constexpr uint8_t  SPIEN  = 0x02;
static constexpr uint8_t  MSTEN  = 0x04;
static constexpr uint8_t  LOFF   = 0x20;
static constexpr uint8_t  WREN   = 0x10;
static constexpr uint16_t OFFR = 0x7FFE;
static constexpr uint16_t CFGR = 0x7FFD;
static constexpr uint8_t  MDIS   = 0x01;
static constexpr uint8_t  ECHO   = 0x02;
static constexpr uint8_t  ASCII  = 0x04; // was ROMDIS
static constexpr uint8_t  K4     = 0x08;
static constexpr uint8_t  SUBOFF = 0x30;
// undocumented stuff
static constexpr uint8_t  FPGA_EN   = 0x40; // write: 1 -> enable communication with FPGA commands ???
static constexpr uint8_t  FPGA_WAIT = 0x80; // read: ready signal ??? (1 = ready)
static constexpr uint16_t FPGA_REG  = 0x7FFC; // bi-direction 8-bit communication channel

[[nodiscard]] static const AmdFlash::ValidatedChip& getFlashChip(
	const DeviceConfig& config, const Rom& rom)
{
	auto name = config.getChildData("flash", "");
	auto size = rom.size();
	if (name == "S29GL01GP" || (name.empty() && size > 0x4000000)) return AmdFlashChip::S29GL01GP;
	if (name == "S29GL512P" || (name.empty() && size > 0x2000000)) return AmdFlashChip::S29GL512P;
	if (name == "S29GL256P" || (name.empty() && size > 0x1000000)) return AmdFlashChip::S29GL256P;
	if (name == "S29GL128P" || (name.empty() && size > 0x0800000)) return AmdFlashChip::S29GL128P;
	if (name.empty() || name == "S29GL064N") return AmdFlashChip::S29GL064N90TFI04;
	throw MSXException("Yamanooto: unknown flash chip: ", name);
}

Yamanooto::Yamanooto(DeviceConfig& config, Rom&& rom_)
	: MSXRom(config, std::move(rom_))
	, romBlockDebug(*this)
	, flash(rom, getFlashChip(config, rom), {}, config)
	, scc(getName() + " SCC", config, getCurrentTime(), SCC::Mode::Compatible)
	, psg(getName() + " PSG", DummyAY8910Periphery::instance(), config,
	      getCurrentTime(), AY8910::Type::AY8910)
	, sdCard(DeviceConfig(config, config.findChild("sdcard")))
{
	// Tests show that the PSG has higher volume than the scc. See
	//   https://www.msx.org/forum/msx-talk/openmsx/openmsx-cartridge-type?page=2#comment-470014
	//   https://msx.pics/images/2024/12/23/yamanooto_volume_comparison.png
	psg.setSoftwareVolume(3.0f, getCurrentTime());

	scc.setBalance(0,  0.00f);
	scc.setBalance(1, -0.67f);
	scc.setBalance(2,  0.67f);
	scc.setBalance(3, -0.67f);
	scc.setBalance(4,  0.67f);
	scc.postSetBalance();

	getCPUInterface().register_IO_Out_range(0x10, 2, this);
	powerUp(getCurrentTime());
}

Yamanooto::~Yamanooto()
{
	writeConfigReg(0); // unregister A0-A2 ports
	getCPUInterface().unregister_IO_Out_range(0x10, 2, this);
}

void Yamanooto::powerUp(EmuTime time)
{
	scc.powerUp(time);
	reset(time);
}

void Yamanooto::reset(EmuTime time)
{
	// TODO is offsetReg changed by reset?
	// TODO are all bits in configReg set to zero?   (also bit 0,1)
	enableReg = 0;
	offsetReg = 0;
	writeConfigReg(0);
	fpgaFsm = 0;
	masterOffsetReg = 0;
	spiCon = 0;
	sdat = 0xFF;

	ranges::iota(bankRegs, uint16_t(0));
	ranges::iota(rawBanks, uint8_t(0));
	sccMode = 0;
	scc.reset(time);

	psgLatch = 0;
	psg.reset(time);

	flash.reset();

	invalidateDeviceRCache(); // flush all to be sure
}

void Yamanooto::writeConfigReg(byte value)
{
	if ((value ^ configReg) & ECHO) {
		if (value & ECHO) {
			getCPUInterface().register_IO_Out_range(0xA0, 2, this);
		} else {
			getCPUInterface().unregister_IO_Out_range(0xA0, 2, this);
		}
	}
	configReg = value;
}

bool Yamanooto::isSCCAccess(uint16_t address) const
{
	if (configReg & (K4 | ASCII)) return false; // only Konami5 has the SCC

	// This uses the raw bank registers (not adjusted with offset register),
	//   see: https://github.com/openMSX/openMSX/issues/1992
	if (sccMode & 0x20) {
		// SCC+   range: 0xB800..0xBFFF,  excluding 0xBFFE-0xBFFF
		return  (rawBanks[3] & 0x80)          && (0xB800 <= address) && (address < 0xBFFE);
	} else {
		// SCC    range: 0x9800..0x9FFF
		return ((rawBanks[2] & 0x3F) == 0x3F) && (0x9800 <= address) && (address < 0xA000);
	}
}

unsigned Yamanooto::getFlashAddr(unsigned addr) const
{
	unsigned page8kB = (addr >> 13) - 2;
	assert(page8kB < 4); // must be inside [0x4000, 0xBFFF]
	unsigned bank = bankRegs[page8kB] & ((flash.size() >> 13) - 1); // 8MB: 0x3FF
	return (bank << 13) | (addr & 0x1FFF);
}

unsigned Yamanooto::getOffset() const
{
	unsigned off = unsigned(offsetReg) + masterOffsetReg;
	return (enableReg & LOFF) ? (off << 8) // 2MB steps
	                          : ((off << 2) | ((configReg & SUBOFF) >> 4));
}

bool Yamanooto::spiSelected() const
{
	// chip select: SPICON bit 4, or the deprecated bit 6 of CFGR
	return (spiCon & 0x10) || (configReg & FPGA_EN);
}

void Yamanooto::setBank(unsigned page8kB, unsigned value, byte raw)
{
	bankRegs[page8kB] = narrow_cast<uint16_t>(value);
	rawBanks[page8kB] = raw;
	invalidateDeviceRCache(0x4000 + 0x2000 * page8kB, 0x2000);
	invalidateDeviceRCache((0x4000 + 0x2000 * page8kB) ^ 0x8000, 0x2000); // mirror
}

[[nodiscard]] static uint16_t mirror(uint16_t address)
{
	if (address < 0x4000 || 0xC000 <= address) {
		// mirror 0x4000 <-> 0xc000   /   0x8000 <-> 0x0000
		address ^= 0x8000; // real hw probably just ignores upper address bit
	}
	assert((0x4000 <= address) && (address < 0xC000));
	return address;
}

static constexpr std::array<byte, 4 + 1> FPGA_ID = {
	0xFF, // idle
	0x1F, 0x23, 0x00, 0x00, // TODO check last 2
};
byte Yamanooto::peekMem(uint16_t address, EmuTime time) const
{
	address = mirror(address);

	// 0x7ffc-0x7fff
	if (FPGA_REG <= address && address <= ENAR && (enableReg & REGEN)) {
		switch (address) {
		case FPGA_REG:
			if (!spiSelected()) return 0xFF; // TODO check this
			if (spiCon & 0x01) return sdat; // SD card
			assert(fpgaFsm < 5);
			return FPGA_ID[fpgaFsm];
		case CFGR: return configReg | FPGA_WAIT; // not-busy
		case OFFR:
			if (enableReg & SPIEN) {
				// SPICON: RDY (always), CD, CS and SPI mode
				return byte(0x80 | (sdCard.isPresent() ? 0x40 : 0x00) | (spiCon & 0x13));
			}
			return offsetReg; // also with MSTEN: MOFFR is write only
		case ENAR: return enableReg;
		default: UNREACHABLE;
		}
	}

	// 0x9800-0x9FFF or 0xB800-0xBFFD
	if (isSCCAccess(address)) {
		return scc.peekMem(narrow_cast<uint8_t>(address & 0xFF), time);
	}
	return flash.peek(getFlashAddr(address), time);
}

byte Yamanooto::readMem(uint16_t address, EmuTime time)
{
	// 0x7ffc-0x7fff  (NOT mirrored)
	if (FPGA_REG <= address && address <= ENAR && (enableReg & REGEN)) {
		return peekMem(address, time);
	}
	address = mirror(address);

	// 0x9800-0x9FFF or 0xB800-0xBFFD
	if (isSCCAccess(address)) {
		return scc.readMem(narrow_cast<uint8_t>(address & 0xFF), time);
	}
	return flash.read(getFlashAddr(address), time);
}

const byte* Yamanooto::getReadCacheLine(uint16_t address) const
{
	if (((address & CacheLine::HIGH) == (ENAR & CacheLine::HIGH)) && (enableReg & REGEN)) {
		return nullptr; // Yamanooto registers, non-cacheable
	}
	address = mirror(address);
	if (isSCCAccess(address)) return nullptr;
	return flash.getReadCacheLine(getFlashAddr(address));
}

void Yamanooto::writeMem(uint16_t address, byte value, EmuTime time)
{
	// 0x7ffc-0x7fff  (NOT mirrored)
	if (FPGA_REG <= address && address <= ENAR) {
		if (address == ENAR) {
			enableReg = value;
		} else if (enableReg & REGEN) {
			switch (address) {
			case FPGA_REG:
				if (!spiSelected()) break;
				if (spiCon & 0x01) { // SD card (01: fast, 11: slow)
					sdat = sdCard.transfer(value, false);
					break;
				}
				switch (fpgaFsm) {
				case 0:
					if (value == 0x9f) { // read ID command ??
						++fpgaFsm;
					}
					break;
				case 1: case 2: case 3:
					++fpgaFsm;
					break;
				case 4:
					fpgaFsm = 0;
					break;
				default:
					UNREACHABLE;
				}
				break;
			case CFGR:
				writeConfigReg(value);
				break;
			case OFFR:
				if (enableReg & SPIEN) {
					if ((spiCon & 0x10) && !(value & 0x10) && (spiCon & 0x01)) {
						// CS released: tell the card
						sdCard.transfer(0xFF, true);
					}
					spiCon = value & 0x13;
				} else if (enableReg & MSTEN) {
					masterOffsetReg = value;
				} else {
					offsetReg = value; // does NOT immediately switch bankRegs
					configReg &= ~SUBOFF; // writing OFFR clears SUBOFF
				}
				break;
			default:
				UNREACHABLE;
			}
		}
		invalidateDeviceRCache();
	}
	bool isReg = (FPGA_REG <= address) && (address <= ENAR); // before mirroring
	address = mirror(address);
	unsigned page8kB = (address >> 13) - 2;

	if (enableReg & WREN) {
		// write to flash rom
		flash.write(getFlashAddr(address), value, time);
		invalidateDeviceRCache(); // needed ?
	} else {
		auto invalidateCache = [&](unsigned start, unsigned size) {
			invalidateDeviceRCache(start, size);
			invalidateDeviceRCache(start ^ 0x8000, size); // mirror
		};
		auto offset = getOffset();
		if (configReg & ASCII) {
			if (((configReg & MDIS) == 0) && !isReg &&
			    (0x6000 <= address) && (address < 0x8000)) {
				if (configReg & K4) {
					// ASCII16: 6000h-67FFh -> 4000h-7FFFh,
					//          7000h-77FFh -> 8000h-BFFFh
					if ((address & 0x0800) == 0) {
						unsigned region = (address & 0x1000) ? 2 : 0;
						unsigned b = ((2u * value) + offset) & 0xFFFF;
						setBank(region + 0, b,     value);
						setBank(region + 1, b + 1, value);
					}
				} else {
					// ASCII8: 6000h, 6800h, 7000h, 7800h
					setBank((address >> 11) & 3, (value + offset) & 0xFFFF, value);
				}
			}
		} else if (configReg & K4) {
			// Konami-4
			if (((configReg & MDIS) == 0) && (0x6000 <= address)) {
				// bank 0 is NOT switchable, but it keeps the
				// value it had before activating K4 mode
				bankRegs[page8kB] = (value + offset) & 0xFFFF;
				rawBanks[page8kB] = value;
				invalidateCache(0x4000 + 0x2000 * page8kB, 0x2000);
			}
		} else {
			// 0x9800-0x9FFF or 0xB800-0xBFFD
			if (isSCCAccess(address)) {
				scc.writeMem(narrow_cast<uint8_t>(address & 0xFF), value, time);
			}

			// FERPECT: like the Konami SCC-I (SCC+), a bank in RAM mode
			// (SCC mode register bit 4: all banks, bits 0/1: bank 0/1,
			// bits 2+5: bank 2) ignores bank switch writes. This matches
			// a real Yamanooto in a Panasonic FS-A1ST, where the
			// Spanish SD Snatcher (it writes 3Fh to BFFEh) crashes.
			bool ramBank = (sccMode & 0x10) ||
				((page8kB == 0) && (sccMode & 0x01)) ||
				((page8kB == 1) && (sccMode & 0x02)) ||
				((page8kB == 2) && ((sccMode & 0x24) == 0x24));

			// Konami-SCC
			if (!ramBank && ((address & 0x1800) == 0x1000) && ((configReg & MDIS) == 0)) {
				// [0x5000,0x57FF] [0x7000,0x77FF]
				// [0x9000,0x97FF] [0xB000,0xB7FF]
				bankRegs[page8kB] = (value + offset) & 0xFFFF;
				rawBanks[page8kB] = value;
				invalidateCache(0x4000 + 0x2000 * page8kB, 0x2000);
			}

			// SCC mode register
			if ((address & 0xFFFE) == 0xBFFE) {
				sccMode = value;
				scc.setMode((value & 0x20) ? SCC::Mode::Plus
				                           : SCC::Mode::Compatible);
				invalidateCache(0x9800, 0x800);
				invalidateCache(0xB800, 0x800);
			}
		}
	}
}

byte* Yamanooto::getWriteCacheLine(uint16_t /*address*/)
{
	return nullptr;
}

byte Yamanooto::peekIO(uint16_t /*port*/, EmuTime /*time*/) const
{
	return 0xff;
}

byte Yamanooto::readIO(uint16_t /*port*/, EmuTime /*time*/)
{
	// PSG is not readable
	return 0xff; // should never be called
}

void Yamanooto::writeIO(uint16_t port, byte value, EmuTime time)
{
	if (port & 1) { // 0x11 or 0xA1
		psg.writeRegister(psgLatch, value, time);
	} else { // 0x10 or 0xA0
		psgLatch = value & 0x0F;
	}
}

// version 1: initial version
// version 2: added 'rawBanks'
template<typename Archive>
void Yamanooto::serialize(Archive& ar, unsigned version)
{
	ar.serialize(
		"flash", flash,
		"scc", scc,
		"psg", psg,
		"bankRegs", bankRegs,
		"enableReg", enableReg,
		"offsetReg", offsetReg,
		"configReg", configReg,
		"sccMode", sccMode,
		"psgLatch", psgLatch,
		"fpgaFsm", fpgaFsm
	);
	if (ar.versionAtLeast(version, 2)) {
		ar.serialize("rawBanks", rawBanks);
	} else {
		// Could be wrong, but the best we can do?
		auto offset = (offsetReg << 2) | ((configReg & SUBOFF) >> 4);
		for (auto [b, r] : std::views::zip(bankRegs, rawBanks)) {
			r = uint8_t(b - offset);
		}
	}
	if (ar.versionAtLeast(version, 3)) {
		ar.serialize("masterOffsetReg", masterOffsetReg,
		             "spiCon", spiCon,
		             "sdat", sdat,
		             "sdCard", sdCard);
	}
}
INSTANTIATE_SERIALIZE_METHODS(Yamanooto);
REGISTER_MSXDEVICE(Yamanooto, "Yamanooto");


unsigned Yamanooto::Blocks::readExt(unsigned address)
{
	const auto& dev = OUTER(Yamanooto, romBlockDebug);
	address = mirror(narrow<uint16_t>(address));
	unsigned page8kB = (address >> 13) - 2;
	return dev.bankRegs[page8kB];
}

} // namespace openmsx
