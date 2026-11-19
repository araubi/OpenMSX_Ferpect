// Based on code written by:
//   (2017) NataliaPC aka @ishwin74
//   Under GPL License

#include "TsxImage.hh"

#include "TsxParser.hh"

#include "CliComm.hh"
#include "File.hh"
#include "FilePool.hh"
#include "Filename.hh"
#include "MSXException.hh"

#include "xrange.hh"

#include <algorithm>

namespace openmsx {

TsxImage::TsxImage(const Filename& filename, FilePool& filePool, CliComm& cliComm)
{
	File file(filename.getResolved());
	try {
		TsxParser parser(file.mmap<const uint8_t>());

		// Move the parsed waveform here
		output = std::move(parser.stealOutput());
		index.reserve(output.size() / INDEX_STEP + 1);
		for (auto i : xrange(output.size())) {
			if ((i % INDEX_STEP) == 0) index.push_back(totalTStates);
			totalTStates += TsxParser::segmentLength(output[i]);
		}

		// Translate the TsxReader-filetype to a CassetteImage-filetype
		if (auto type = parser.getFirstFileType()) {
			setFirstFileType([&] {
				switch (*type) {
				case TsxParser::FileType::ASCII:  return CassetteImage::FileType::ASCII;
				case TsxParser::FileType::BINARY: return CassetteImage::FileType::BINARY;
				case TsxParser::FileType::BASIC:  return CassetteImage::FileType::BASIC;
				default:                          return CassetteImage::FileType::UNKNOWN;
				}
			}(), filename);
		}

		// Print embedded messages
		for (const auto& msg : parser.getMessages()) {
			cliComm.printInfo(msg);
		}
	} catch (const std::string& msg) {
		throw MSXException(filename.getOriginal(), ": ", msg);
	}

	// Conversion successful, now calculate sha1sum
	setSha1Sum(filePool.getSha1Sum(file, filename.getResolved()));
}

int8_t TsxImage::getValueAt(uint64_t tState, Cursor& cursor) const
{
	if (tState >= totalTStates) return 0;

	if (tState < cursor.start) {
		// Going back in time (e.g. rewind): restart from the index.
		auto it = std::ranges::upper_bound(index, tState);
		auto block = size_t(it - index.begin()) - 1;
		cursor.segment = block * INDEX_STEP;
		cursor.start = index[block];
	}
	while (true) {
		auto segment = output[cursor.segment];
		auto len = TsxParser::segmentLength(segment);
		if (tState < cursor.start + len) {
			using enum TsxParser::Level;
			switch (TsxParser::segmentLevel(segment)) {
				case HIGH: return 127;
				case LOW:  return -127;
				default:   return 0;
			}
		}
		cursor.start += len;
		++cursor.segment;
		if ((cursor.segment % INDEX_STEP) == 0) {
			// Far ahead (e.g. fast forward)? Then use the index.
			auto block = cursor.segment / INDEX_STEP;
			if ((block + 1 < index.size()) && (index[block + 1] <= tState)) {
				auto it = std::ranges::upper_bound(index, tState);
				block = size_t(it - index.begin()) - 1;
				cursor.segment = block * INDEX_STEP;
				cursor.start = index[block];
			}
		}
	}
}

int16_t TsxImage::getSampleAt(EmuTime time) const
{
	auto tState = uint64_t(time.toDouble() * TsxParser::TZX_Z80_FREQ);
	return int16_t(getValueAt(tState, emuCursor) * 256);
}

EmuTime TsxImage::getEndTime() const
{
	return EmuTime::zero() +
	       EmuDuration::sec(double(totalTStates) / TsxParser::TZX_Z80_FREQ);
}

unsigned TsxImage::getFrequency() const
{
	return TsxParser::OUTPUT_FREQUENCY;
}

void TsxImage::fillBuffer(unsigned pos, std::span<float*, 1> bufs, unsigned num) const
{
	// Audio output only: sample the waveform at OUTPUT_FREQUENCY.
	auto toTStates = [](uint64_t p) {
		return p * TsxParser::TZX_Z80_FREQ / TsxParser::OUTPUT_FREQUENCY;
	};
	if (toTStates(pos) < totalTStates) {
		for (auto i : xrange(num)) {
			bufs[0][i] = getValueAt(toTStates(uint64_t(pos) + i), audioCursor);
		}
	} else {
		bufs[0] = nullptr;
	}
}

float TsxImage::getAmplificationFactorImpl() const
{
	return 1.0f / 128;
}

} // namespace openmsx
