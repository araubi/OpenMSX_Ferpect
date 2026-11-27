#ifndef NATIVE_MENU_HH
#define NATIVE_MENU_HH

// FERPECT: description of a native menu bar (used on macOS, see
// src/macos/MacFrontEnd.hh). This is plain data: the platform code turns it
// into real menus and calls 'action' when an item is chosen.

#include <functional>
#include <string>
#include <vector>

namespace openmsx {

struct NativeMenuItem
{
	enum Mod : unsigned { CMD = 1, SHIFT = 2, ALT = 4, CTRL = 8 };
	enum class Standard {
		NONE,       // a normal item: 'action' is called
		SEPARATOR,
		// items handled by the operating system itself
		HIDE, HIDE_OTHERS, SHOW_ALL, QUIT, SERVICES,
		MINIMIZE, ZOOM, CLOSE, BRING_ALL_TO_FRONT,
	};
	enum class Role { NORMAL, APP, WINDOW, HELP }; // only for top-level menus

	std::string title;
	std::string key;        // key equivalent, e.g. "o" (empty: none)
	unsigned mods = CMD;    // modifiers of the key equivalent
	Standard standard = Standard::NONE;
	Role role = Role::NORMAL;
	bool enabled = true;
	bool checked = false;
	std::function<void()> action;
	std::vector<NativeMenuItem> children; // not empty: this is a submenu
};

} // namespace openmsx

#endif
