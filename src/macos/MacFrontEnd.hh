#ifndef MAC_FRONT_END_HH
#define MAC_FRONT_END_HH

// FERPECT: native macOS user interface (menu bar, file panels, ...).
//
// Only MacFrontEnd.mm (compiled on macOS) knows about Cocoa. On the other
// systems these functions do nothing, so the callers need no #ifdef.

#include "NativeMenu.hh"

#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

struct SDL_Window;

namespace openmsx::mac {

#ifdef __APPLE__

inline constexpr bool NATIVE_UI = true;

/** Replace the menu bar by the menus that 'builder' describes. The builder is
  * called again each time a menu is about to be shown (or a key equivalent
  * is searched), so the items always show the current state. */
void installMenuBar(std::function<std::vector<NativeMenuItem>()> builder);

/** Things that make the main (SDL) window behave like other Mac windows. */
void configureMainWindow(SDL_Window* window);

/** Standard open panel (modal). 'extensions' without the dot, empty = any. */
[[nodiscard]] std::optional<std::string> runOpenPanel(
	const std::string& title, const std::vector<std::string>& extensions,
	bool chooseDirectory, const std::string& startDir);

/** Standard save panel (modal). */
[[nodiscard]] std::optional<std::string> runSavePanel(
	const std::string& title, const std::vector<std::string>& extensions,
	const std::string& startDir);

/** Standard "About" panel. */
void showAbout(const std::string& version);

/** Open a file or URL with the application macOS has for it. */
void openURL(const std::string& url);

/** The text in the language of the user (es.lproj/Localizable.strings in
  * the application bundle), or the English text itself. With 'language'
  * (e.g. "es") the text in that language, whatever the one of the user. */
[[nodiscard]] std::string tr(std::string_view english, const char* language = nullptr);

#else

inline constexpr bool NATIVE_UI = false;

inline void installMenuBar(std::function<std::vector<NativeMenuItem>()> /*builder*/) {}
inline void configureMainWindow(SDL_Window* /*window*/) {}
[[nodiscard]] inline std::optional<std::string> runOpenPanel(
	const std::string& /*title*/, const std::vector<std::string>& /*extensions*/,
	bool /*chooseDirectory*/, const std::string& /*startDir*/) { return {}; }
[[nodiscard]] inline std::optional<std::string> runSavePanel(
	const std::string& /*title*/, const std::vector<std::string>& /*extensions*/,
	const std::string& /*startDir*/) { return {}; }
inline void showAbout(const std::string& /*version*/) {}
inline void openURL(const std::string& /*url*/) {}
[[nodiscard]] inline std::string tr(std::string_view english, const char* /*language*/ = nullptr) { return std::string(english); }

#endif

} // namespace openmsx::mac

#endif
