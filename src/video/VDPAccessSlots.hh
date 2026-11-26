#ifndef VDPACCESSSLOTS_HH
#define VDPACCESSSLOTS_HH

#include "VDP.hh"
#include "VDPCmdCache.hh"

#include "narrow.hh"

#include <cassert>
#include <cstdint>
#include <span>
#include <utility>

namespace openmsx::VDPAccessSlots {

inline constexpr int TICKS = VDP::TICKS_PER_LINE;

/** Minimum distance until the next VRAM access. */
enum class Delta : int {
	D0        =  0 * TICKS, // These 2 are internal helpers
	D1        =  1 * TICKS,
	CPU_16    =  2 * TICKS, // These 3 are for CPU access delays (V99x8)
	CPU_28    =  3 * TICKS, //                                   (TMS99x8)
	// Like CPU_16, but without skipping the slots the CPU cannot be served
	// in: the slot it would have been granted, which the VDP spends on a
	// dummy read when the two differ.
	CPU_16_ANY =  4 * TICKS,
	CMD_24    =  5 * TICKS, // The remaining ones are command engine delays
	CMD_32    =  6 * TICKS, //   counted in 'memory cycles' rather than 'VDP cycles'
	CMD_36    =  7 * TICKS, //   see the comment about 'pad' in
	CMD_46    =  8 * TICKS, //   VDPAccessSlots.cc
	CMD_60    =  9 * TICKS,
	CMD_72    = 10 * TICKS,
	CMD_84    = 11 * TICKS,
	CMD_88    = 12 * TICKS,
	CMD_36_68 = 13 * TICKS, // 36+68 = 104
	CMD_46_58 = 13 * TICKS, // 46+58 = 104 (notice: duplicate!)
	CMD_84_36 = 14 * TICKS, // 84+36 = 120
	CMD_60_68 = 15 * TICKS, // 60+68 = 128
	CMD_72_58 = 16 * TICKS, // 72+58 = 130
	// The delay between the write to R#46 that starts a command and the
	// command's first VRAM access. Measured from the rising edge of /CSW as
	// 45, 46, 58, 70, 82 and 94 cycles; the values below are those plus the
	// 18 cycles between openMSX's port-write timestamp and that edge. The
	// startup is a wait like any other, so it is counted in memory cycles
	// and it gets the sprite addend.
	CMD_START_63  = 17 * TICKS, // POINT
	CMD_START_64  = 18 * TICKS, // LMMM
	CMD_START_76  = 19 * TICKS, // LMCM
	CMD_START_88  = 12 * TICKS, // LMMV, LMMC, PSET, SRCH  (= CMD_88!)
	CMD_START_100 = 20 * TICKS, // HMMM, YMMM
	CMD_START_112 = 21 * TICKS, // HMMV, LINE, HMMC
};
static constexpr int NUM_DELTAS = 22;
/** The CPU access delays in the 'Delta' enum: CPU_16, CPU_28 and CPU_16_ANY. */
static constexpr int FIRST_CPU_DELTA = 2;
static constexpr int LAST_CPU_DELTA = 5; // exclusive
/** The one of those that does use the slots the CPU cannot be served in. */
static constexpr int CPU_ANY_DELTA = 4;
/** The command engine delays in the 'Delta' enum: the steps and the startup
  * delays. These get the sprite addend; they and the CPU delays above are all
  * subject to the memory-cycle counting. */
static constexpr int FIRST_CMD_DELTA = 5;
static constexpr int LAST_CMD_DELTA = NUM_DELTAS; // exclusive

// --- V9968 (buppu3) high-speed command timing, FERPECT approximation ---
// buppu3's fork runs the VDP clock 4 times faster and has its own slot tables
// for the V9968. FERPECT keeps openMSX's clock and its measured V99x8 tables,
// so the high-speed delays are counted here in quarter VDP cycles, with a
// VRAM slot every 16 quarter cycles (as in the V9968 screen-off table) and
// without the slots the display takes away. Close on average, not exact.
static constexpr int V9968_MEMORY_ACCESS_TIME = 7;

/** Advance 'q' (quarter VDP cycles) by 'delay', the cache penalty and 'wait'. */
[[nodiscard]] constexpr unsigned getAccessSlotQuarter(
	unsigned q, int delay, int wait, VDPCmdCache::CachePenalty penalty)
{
	using enum VDPCmdCache::CachePenalty;
	auto slot = [&](int extra) { // wait for a VRAM slot, then the access
		q += ((16 + 1 - (q & 15)) & 15) + V9968_MEMORY_ACCESS_TIME + extra;
	};
	q += delay;
	switch (penalty) {
	case CACHE_NONE: case CACHE_FLUSH_0: break;
	case CACHE_READ_HIT: case CACHE_WRITE_HIT: case CACHE_WRITE_MISS:
		q += 1; break;
	case CACHE_READ_MISS:  q += 1; slot(1); break;
	case CACHE_READ_FLUSH: q += 1; slot(1); slot(1); break;
	case CACHE_WRITE_FLUSH: case CACHE_FLUSH_1: q += 1; slot(0); break;
	case CACHE_FLUSH_2: q += 1; slot(0); q += 1; slot(0); break;
	case CACHE_FLUSH_3: q += 1; slot(0); q += 1; slot(0); q += 1; slot(0); break;
	case CACHE_FLUSH_4: q += 1; slot(0); q += 1; slot(0); q += 1; slot(0); q += 1; slot(0); break;
	}
	return q + wait;
}

/** VDP-VRAM access slot calculator, meant to be used in the inner loops of the
  * VDPCmdEngine commands. Code optimized for the case that:
  *  - timing remains constant (sprites/display enable/disable)
  *  - there are more calls to next() and limitReached() than to getTime()
  */
class Calculator
{
public:
	/** This shouldn't be called directly, instead use getCalculator(). */
	Calculator(EmuTime frame, EmuTime time,
	           EmuTime limit_, std::span<const uint8_t, NUM_DELTAS * TICKS> tab_)
		: ref(frame), tab(tab_)
	{
		assert(frame <= time);
		assert(frame <= limit_);
		// not required that time <= limit

		ticks = narrow<int>(ref.getTicksTill(time));
		limit = narrow<int>(ref.getTicksTill(limit_));
		int lines = ticks / TICKS;
		ticks -= lines * TICKS;
		limit -= lines * TICKS; // might be negative
		ref   += lines * TICKS;
		assert(0 <= ticks); assert(ticks < TICKS);
	}

	/** Has 'time' advanced to or past 'limit'? */
	[[nodiscard]] bool limitReached() const {
		return ticks >= limit;
	}

	/** Get the current time. Initially this will return the 'time'
	  * constructor parameter. Each call to next() will increase this
	  * value. */
	[[nodiscard]] EmuTime getTime() const {
		return ref.getFastAdd(ticks);
	}

	/** Advance time to the earliest access slot that is at least 'delta'
	  * ticks later than the current time. */
	void next(Delta delta) {
		ticks += tab[std::to_underlying(delta) + ticks];
		if (ticks >= TICKS) [[unlikely]] {
			ticks -= TICKS;
			limit -= TICKS;
			ref   += TICKS;
		}
	}

	/** V9968 high-speed step, see getAccessSlotQuarter(). */
	void nextHs(int delay, int wait, VDPCmdCache::CachePenalty penalty) {
		unsigned q = getAccessSlotQuarter(unsigned(ticks) * 4 + frac,
		                                  delay, wait, penalty);
		ticks = narrow_cast<int>(q >> 2);
		frac  = narrow_cast<int>(q & 3);
		while (ticks >= TICKS) [[unlikely]] {
			ticks -= TICKS;
			limit -= TICKS;
			ref   += TICKS;
		}
	}

private:
	int ticks;
	int frac = 0; // quarter cycles, only used by nextHs()
	int limit;
	VDP::VDPClock ref;
	std::span<const uint8_t, NUM_DELTAS * TICKS> tab;
};

/** Return the time of the next available access slot that is at least 'delta'
  * cycles later than 'time'. The start of the current 'frame' is needed for
  * reference. */
[[nodiscard]] EmuTime getAccessSlot(EmuTime frame, EmuTime time, Delta delta,
                      const VDP& vdp);

/** V9968 high-speed variant, see getAccessSlotQuarter(). */
[[nodiscard]] EmuTime getAccessSlot(EmuTime frame, EmuTime time, int delay, int wait,
                      VDPCmdCache::CachePenalty penalty, const VDP& vdp);

/** When many calls to getAccessSlot() are needed, it's more efficient to
  * instead use this function. */
[[nodiscard]] Calculator getCalculator(
	EmuTime frame, EmuTime time, EmuTime limit,
	const VDP& vdp);

/** The largest interval paddingCycles() accepts. */
inline constexpr int MAX_PADDING_SPAN = 8;

/** How many cycles of line padding complete in the interval (t, t + n], where
  * 't' is at position 'tick' in its line: the number of cycles by which that
  * interval is longer in VDP cycles than in the VDP's memory cycles. Only for
  * short intervals; see the comment about 'pad' in VDPAccessSlots.cc. */
[[nodiscard]] int paddingCycles(int tick, int n, const VDP& vdp);

/** Is the CPU slot at line position 'slotTick' a 'late' one? Those hand out
  * their grant 2 cycles later than the rest, and release the CPU's request
  * buffer one cycle before their access instead of one cycle after. */
[[nodiscard]] bool isLateCpuSlot(int slotTick, const VDP& vdp);

} // namespace openmsx::VDPAccessSlots

#endif
