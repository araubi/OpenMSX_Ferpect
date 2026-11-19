// Based on code written by:
//   (2017) NataliaPC aka @ishwin74
//   Under GPL License

#ifndef TSXIMAGE_HH
#define TSXIMAGE_HH

#include "CassetteImage.hh"

#include <cstdint>
#include <vector>

namespace openmsx {

class CliComm;
class Filename;
class FilePool;

class TsxImage final : public CassetteImage
{
public:
	TsxImage(const Filename& fileName, FilePool& filePool, CliComm& cliComm);

	// CassetteImage
	[[nodiscard]] int16_t getSampleAt(EmuTime time) const override;
	[[nodiscard]] EmuTime getEndTime() const override;
	[[nodiscard]] unsigned getFrequency() const override;
	void fillBuffer(unsigned pos, std::span<float*, 1> bufs, unsigned num) const override;
	[[nodiscard]] float getAmplificationFactorImpl() const override;

private:
	// Lookups are mostly done at (slowly) increasing times, so remember
	// where the previous lookup ended. One cursor for the signal the MSX
	// reads, one for the audio output (they're at slightly different
	// positions).
	struct Cursor {
		size_t segment = 0;
		uint64_t start = 0; // in T-states
	};
	[[nodiscard]] int8_t getValueAt(uint64_t tState, Cursor& cursor) const;

private:
	// The waveform, as segments of constant level (see TsxParser).
	/*const*/ std::vector<uint16_t> output;
	// Start (in T-states) of every INDEX_STEP-th segment, for fast lookup.
	static constexpr unsigned INDEX_STEP = 1024;
	/*const*/ std::vector<uint64_t> index;
	uint64_t totalTStates = 0;

	mutable Cursor emuCursor;
	mutable Cursor audioCursor;
};

} // namespace openmsx

#endif
