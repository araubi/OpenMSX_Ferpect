#include "ImGuiManager.hh"

#include "ImGuiBreakPoints.hh"
#include "ImGuiCheatFinder.hh"
#include "ImGuiConnector.hh"
#include "ImGuiConsole.hh"
#include "ImGuiCpp.hh"
#include "ImGuiDebugger.hh"
#include "ImGuiDiskManipulator.hh"
#include "ImGuiHelp.hh"
#include "ImGuiIoPorts.hh"
#include "ImGuiKeyboard.hh"
#include "ImGuiMachine.hh"
#include "ImGuiMedia.hh"
#include "ImGuiMessages.hh"
#include "ImGuiMsxMusicViewer.hh"
#include "ImGuiOpenFile.hh"
#include "ImGuiOsdIcons.hh"
#include "ImGuiPalette.hh"
#include "ImGuiPlotterViewer.hh"
#include "ImGuiRasterViewer.hh"
#include "ImGuiReverseBar.hh"
#include "ImGuiSCCViewer.hh"
#include "ImGuiSettings.hh"
#include "ImGuiSlotMap.hh"
#include "ImGuiSoundChip.hh"
#include "ImGuiSymbols.hh"
#include "ImGuiTools.hh"
#include "ImGuiTraceViewer.hh"
#include "ImGuiTrainer.hh"
#include "ImGuiUtils.hh"
#include "ImGuiVdpRegs.hh"
#include "ImGuiWatchExpr.hh"
#include "ImGuiWaveViewer.hh"

#include "CartridgeSlotManager.hh"
#include "CommandException.hh"
#include "Display.hh"
#include "Event.hh"
#include "EventDistributor.hh"
#include "FileContext.hh"
#include "FileOperations.hh"
#include "FilePool.hh"
#include "GlobalSettings.hh"
#include "HardwareConfig.hh"
#include "MacFrontEnd.hh"
#include "Reactor.hh"
#include "RealDrive.hh"
#include "RomDatabase.hh"
#include "RomInfo.hh"
#include "SettingsConfig.hh"
#include "VDP.hh"
#include "Version.hh"

#include "format.hh"
#include "stl.hh"
#include "strCat.hh"

#include <CustomFont.ii> // icons for ImGuiFileDialog
#include <imgui.h>
#include <imgui_impl_opengl3.h>
#include <imgui_impl_sdl3.h>
#include <imgui_internal.h>

#include <SDL3/SDL.h>

#include <algorithm>

namespace openmsx {

using namespace std::literals;

std::tuple<ImFont*, std::string> ImGuiManager::addFont(zstring_view filename, int fontSize, int faceIndex)
{
	auto& io = ImGui::GetIO();
	if (!filename.empty()) {
		try {
			const auto& context = systemFileContext();

			File file(context.resolve(FileOperations::join("skins", filename)));
			auto fileSize = file.getSize();
			auto ttfData = std::span(
				static_cast<uint8_t*>(ImGui::MemAlloc(fileSize)), fileSize);
			file.read(ttfData);

			std::string name = getFontDisplayName(ttfData, faceIndex, filename);

			ImFontConfig fontConfig;
			fontConfig.FontNo = faceIndex;
			auto* result = io.Fonts->AddFontFromMemoryTTF(
				ttfData.data(), // transfer ownership of 'ttfData' buffer
				narrow<int>(ttfData.size()), narrow<float>(fontSize),
				&fontConfig, nullptr);
			if (!result) {
				throw MSXException("parse error, possibly invalid faceIndex");
			}
			return {result, name};
		} catch (MSXException& e) {
			getCliComm().printWarning("Couldn't load font: ", filename, ": ", e.getMessage(),
						". Reverted to builtin font");
		}
	}
	return {io.Fonts->AddFontDefault(), "(default)"}; // embedded "ProggyClean.ttf", size 13
}

void ImGuiManager::loadFont()
{
	ImGuiIO& io = ImGui::GetIO();

	assert(fontProp == nullptr);
	std::tie(fontProp, fontPropName) = addFont(fontPropFilename.getString(), fontPropSize.getInt(), fontPropIndex.getInt());

	//// load icon font file (CustomFont.cpp), only in the default font
	static constexpr std::array<ImWchar, 3> icons_ranges = {ICON_MIN_IGFD, ICON_MAX_IGFD, 0};
	ImFontConfig icons_config; icons_config.MergeMode = true; icons_config.PixelSnapH = true;
	io.Fonts->AddFontFromMemoryCompressedBase85TTF(FONT_ICON_BUFFER_NAME_IGFD, 15.0f, &icons_config, icons_ranges.data());
	// load debugger icons, also only in default font
	ImGuiDebugger::loadIcons();

	assert(fontMono == nullptr);
	std::tie(fontMono, fontMonoName) = addFont(fontMonoFilename.getString(), fontMonoSize.getInt(), fontMonoIndex.getInt());
}

void ImGuiManager::reloadFont()
{
	fontProp = fontMono = nullptr;

	ImGuiIO& io = ImGui::GetIO();
	io.Fonts->Clear();
	loadFont();
}

void ImGuiManager::initializeImGui()
{
	// Setup Dear ImGui context
	IMGUI_CHECKVERSION();
	ImGui::CreateContext();
	ImGuiIO& io = ImGui::GetIO();
	io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard |
	                  //ImGuiConfigFlags_NavEnableGamepad | // TODO revisit this later
	                  ImGuiConfigFlags_DockingEnable |
	                  ImGuiConfigFlags_ViewportsEnable;
	// KEEP-SDL2: The SDL3 backend can make the ImGui windows outside the
	// main window children of the main window (always on top of it and
	// minimized together with it). Keep them independent windows, like
	// with SDL2.
	io.ConfigViewportsNoDefaultParent = true;
	static auto iniFilename = systemFileContext().resolveCreate("imgui.ini");
	io.IniFilename = iniFilename.c_str();

	loadFont();
}

static void cleanupImGui()
{
	ImGui::DestroyContext();
}


ImGuiManager::ImGuiManager(Reactor& reactor_)
	: reactor(reactor_)
	, fontPropFilename(reactor.getCommandController(), "gui_font_default_filename", "TTF font filename for the default GUI font", "DejaVuSans.ttf.gz")
	, fontMonoFilename(reactor.getCommandController(), "gui_font_mono_filename", "TTF font filename for the monospaced GUI font", "DejaVuSansMono.ttf.gz")
	, fontPropIndex(reactor.getCommandController(), "gui_font_default_index", "Variation index for the default GUI font, ttc only.", 0, 0, 100)
	, fontMonoIndex(reactor.getCommandController(), "gui_font_mono_index", "Variation index for the monospaced GUI font. ttc only.", 0, 0, 100)
	, fontPropSize(reactor.getCommandController(), "gui_font_default_size", "size for the default GUI font", 13, 9, 72)
	, fontMonoSize(reactor.getCommandController(), "gui_font_mono_size", "size for the monospaced GUI font", 13, 9, 72)
	, windowPos{SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED}
{
	parts.push_back(this);

	// In order that they appear in the menubar
	machine = std::make_unique<ImGuiMachine>(*this);
	media = std::make_unique<ImGuiMedia>(*this);
	connector = std::make_unique<ImGuiConnector>(*this);
	reverseBar = std::make_unique<ImGuiReverseBar>(*this);
	tools = std::make_unique<ImGuiTools>(*this);
	settings = std::make_unique<ImGuiSettings>(*this);
	debugger = std::make_unique<ImGuiDebugger>(*this);
	help = std::make_unique<ImGuiHelp>(*this);

	breakPoints = std::make_unique<ImGuiBreakPoints>(*this);
	symbols = std::make_unique<ImGuiSymbols>(*this);
	watchExpr = std::make_unique<ImGuiWatchExpr>(*this);
	traceViewer = std::make_unique<ImGuiTraceViewer>(*this);
	ioPorts = std::make_unique<ImGuiIoPorts>(*this);
	vdpRegs = std::make_unique<ImGuiVdpRegs>(*this);
	palette = std::make_unique<ImGuiPalette>(*this);
	plotterViewer = std::make_unique<ImGuiPlotterViewer>(*this);
	rasterViewer = std::make_unique<ImGuiRasterViewer>(*this, *traceViewer);
	osdIcons = std::make_unique<ImGuiOsdIcons>(*this);
	openFile = std::make_unique<ImGuiOpenFile>(*this);
	trainer = std::make_unique<ImGuiTrainer>(*this);
	cheatFinder = std::make_unique<ImGuiCheatFinder>(*this);
	slotMap = std::make_unique<ImGuiSlotMap>(*this);
	sccViewer = std::make_unique<ImGuiSCCViewer>(*this);
	msxMusicViewer = std::make_unique<ImGuiMsxMusicViewer>(*this);
	waveViewer = std::make_unique<ImGuiWaveViewer>(*this);
	diskManipulator = std::make_unique<ImGuiDiskManipulator>(*this);
	soundChip = std::make_unique<ImGuiSoundChip>(*this);
	keyboard = std::make_unique<ImGuiKeyboard>(*this);
	console = std::make_unique<ImGuiConsole>(*this);
	messages = std::make_unique<ImGuiMessages>(*this);
	initializeImGui();

	ImGuiSettingsHandler ini_handler;
	ini_handler.TypeName = "openmsx";
	ini_handler.TypeHash = ImHashStr("openmsx");
	ini_handler.UserData = this;
	//ini_handler.ClearAllFn = [](ImGuiContext*, ImGuiSettingsHandler* handler) { // optional
	//      // Clear all settings data
	//      static_cast<ImGuiManager*>(handler->UserData)->iniClearAll();
	//};
	ini_handler.ReadInitFn = [](ImGuiContext*, ImGuiSettingsHandler* handler) { // optional
	      // Read: Called before reading (in registration order)
	      static_cast<ImGuiManager*>(handler->UserData)->iniReadInit();
	};
	ini_handler.ReadOpenFn = [](ImGuiContext*, ImGuiSettingsHandler* handler, const char* name) -> void* { // required
	        // Read: Called when entering into a new ini entry e.g. "[Window][Name]"
	        return static_cast<ImGuiManager*>(handler->UserData)->iniReadOpen(name);
	};
	ini_handler.ReadLineFn = [](ImGuiContext*, ImGuiSettingsHandler* handler, void* entry, const char* line) { // required
	        // Read: Called for every line of text within an ini entry
	        static_cast<ImGuiManager*>(handler->UserData)->loadLine(entry, line);
	};
	ini_handler.ApplyAllFn = [](ImGuiContext*, ImGuiSettingsHandler* handler) { // optional
	      // Read: Called after reading (in registration order)
	      static_cast<ImGuiManager*>(handler->UserData)->iniApplyAll();
	};
	ini_handler.WriteAllFn = [](ImGuiContext*, ImGuiSettingsHandler* handler, ImGuiTextBuffer* out_buf) { // required
	        // Write: Output every entries into 'out_buf'
	        static_cast<ImGuiManager*>(handler->UserData)->iniWriteAll(*out_buf);
	};
	ImGui::AddSettingsHandler(&ini_handler);

	auto& eventDistributor = reactor.getEventDistributor();
	using enum EventType;
	for (auto type : {MOUSE_BUTTON_UP, MOUSE_BUTTON_DOWN, MOUSE_MOTION, MOUSE_WHEEL,
	                  KEY_UP, KEY_DOWN, TEXT,
	                  WINDOW, FILE_DROP, IMGUI_DELAYED_ACTION, BREAK, CONTINUE, MACHINE_LOADED, QUIT}) {
		eventDistributor.registerEventListener(type, *this, EventDistributor::Priority::IMGUI);
	}

	fontPropFilename.attach(*this);
	fontMonoFilename.attach(*this);
	fontPropSize.attach(*this);
	fontMonoSize.attach(*this);
	fontPropIndex.attach(*this);
	fontMonoIndex.attach(*this);
}

ImGuiManager::~ImGuiManager()
{
	fontMonoSize.detach(*this);
	fontPropSize.detach(*this);
	fontMonoFilename.detach(*this);
	fontPropFilename.detach(*this);
	fontPropIndex.detach(*this);
	fontMonoIndex.detach(*this);

	auto& eventDistributor = reactor.getEventDistributor();
	using enum EventType;
	for (auto type : {MACHINE_LOADED, CONTINUE, BREAK, IMGUI_DELAYED_ACTION, FILE_DROP, WINDOW, TEXT,
	                  KEY_DOWN, KEY_UP,
	                  MOUSE_WHEEL, MOUSE_MOTION, MOUSE_BUTTON_DOWN, MOUSE_BUTTON_UP}) {
		eventDistributor.unregisterEventListener(type, *this);
	}

	cleanupImGui();
}

void ImGuiManager::registerPart(ImGuiPartInterface* part)
{
	assert(!contains(parts, part));
	assert(!contains(toBeAddedParts, part));
	toBeAddedParts.push_back(part);
}

void ImGuiManager::unregisterPart(ImGuiPartInterface* part)
{
	if (auto it1 = std::ranges::find(parts, part); it1 != parts.end()) {
		*it1 = nullptr;
		removeParts = true; // filter nullptr later
	} else if (auto it2 = std::ranges::find(toBeAddedParts, part); it2 != toBeAddedParts.end()) {
		toBeAddedParts.erase(it2); // fine to remove now
	}
}

void ImGuiManager::updateParts()
{
	if (removeParts) {
		removeParts = false;
		std::erase(parts, nullptr);
	}

	append(parts, toBeAddedParts);
	toBeAddedParts.clear();
}

void ImGuiManager::save(ImGuiTextBuffer& buf)
{
	// We cannot query "reactor.getDisplay().getWindowPosition()" here
	// because display may already be destroyed. Instead Display pushes
	// window position to here
	savePersistent(buf, *this, persistentElements);
}

void ImGuiManager::loadLine(std::string_view name, zstring_view value)
{
	loadOnePersistent(name, value, *this, persistentElements);
}

static gl::ivec2 ensureVisible(gl::ivec2 windowPos, gl::ivec2 windowSize)
{
	auto windowTL = windowPos;
	auto windowBR = windowTL + windowSize;
	auto overlaps = [&](const ImGuiPlatformMonitor& monitor) {
		auto monitorTL = trunc(gl::vec2(monitor.MainPos));
		auto monitorBR = monitorTL + trunc(gl::vec2(monitor.MainSize));
		return windowTL.x < monitorBR.x &&
		       windowBR.x > monitorTL.x &&
		       windowTL.y < monitorBR.y &&
		       windowBR.y > monitorTL.y;
	};

	if (const auto& monitors = ImGui::GetPlatformIO().Monitors;
	    !monitors.empty() && std::ranges::none_of(monitors, overlaps)) {
		// window isn't visible in any of the monitors
		// -> place centered on the nearest monitor
		return gl::ivec2(SDL_WINDOWPOS_CENTERED);
	}
	return windowPos; // current placement is fine
}

void ImGuiManager::loadEnd()
{
	auto& display = reactor.getDisplay();
	windowPos = ensureVisible(windowPos, display.getWindowSize());
	display.setWindowPosition(windowPos);
}

Interpreter& ImGuiManager::getInterpreter()
{
	return reactor.getInterpreter();
}

CliComm& ImGuiManager::getCliComm()
{
	return reactor.getCliComm();
}

std::optional<TclObject> ImGuiManager::execute(TclObject command)
{
	try {
		return command.executeCommand(getInterpreter());
	} catch (CommandException&) {
		// ignore
		return {};
	}
}

void ImGuiManager::executeDelayed(std::function<void()> action)
{
	bool wasEmpty = delayedActionQueue.empty();
	delayedActionQueue.push_back(std::move(action));
	if (wasEmpty) {
		reactor.getEventDistributor().distributeEvent(ImGuiDelayedActionEvent());
	}
}

void ImGuiManager::executeDelayed(TclObject command,
                                  const std::function<void(const TclObject&)>& ok,
                                  const std::function<void(const std::string&)>& error)
{
	executeDelayed([this, command, ok, error]() mutable {
		try {
			auto result = command.executeCommand(getInterpreter());
			if (ok) ok(result);
		} catch (CommandException& e) {
			if (error) error(e.getMessage());
		}
	});
}

void ImGuiManager::executeDelayed(TclObject command,
                                  const std::function<void(const TclObject&)>& ok)
{
	executeDelayed(std::move(command), ok,
		[this](const std::string& message) { this->printError(message); });
}

void ImGuiManager::printError(std::string_view message)
{
	getCliComm().printError(message);
}

bool ImGuiManager::signalEvent(const Event& event)
{
	if (const auto* evt = get_event_if<SdlEvent>(event)) {
		const ImGuiIO& io = ImGui::GetIO();
		if (!io.BackendPlatformUserData) {
			// ImGui backend not (yet) initialized (e.g. after 'set renderer none')
			return false;
		}
		const SDL_Event& sdlEvent = evt->getSdlEvent();
		ImGui_ImplSDL3_ProcessEvent(&sdlEvent);
		if ((io.WantCaptureMouse &&
		     sdlEvent.type == one_of(SDL_EVENT_MOUSE_MOTION, SDL_EVENT_MOUSE_WHEEL,
		                             SDL_EVENT_MOUSE_BUTTON_DOWN, SDL_EVENT_MOUSE_BUTTON_UP)) ||
		    (io.WantCaptureKeyboard &&
		     sdlEvent.type == one_of(SDL_EVENT_KEY_DOWN, SDL_EVENT_KEY_UP, SDL_EVENT_TEXT_INPUT))) {
			return true; // block event for lower priority listeners
		}
	} else {
		switch (getType(event)) {
		using enum EventType;
		case QUIT:
			debugger->signalQuit();
			machine->signalQuit();
			break;
		case IMGUI_DELAYED_ACTION: {
			while (!delayedActionQueue.empty()) {
				std::swap(delayedActionQueue, delayedActionQueue2);
				assert(delayedActionQueue.empty());
				for (auto& action : delayedActionQueue2) {
					std::invoke(action);
				}
				delayedActionQueue2.clear();
			}
			// while invoking the delayed actions, more such actions
			// may have been queued, handle those as well via this outer loop
			break;
		}
		case FILE_DROP: {
			const auto& fde = get_event<FileDropEvent>(event);
			droppedFile = fde.getFileName();
			handleDropped = true;
			break;
		}
		case MACHINE_LOADED:
			// Triggers when a new machine gets activated, e.g.:
			// * after a 'step_back' (or any click in the reverse bar).
			// * after a machine instance switch
			// (For now) this triggers the same behavior as BREAK: scroll debugger to PC
			[[fallthrough]];
		case BREAK:
			debugger->signalBreak();
			break;
		case CONTINUE:
			debugger->signalContinue();
			break;
		default:
			UNREACHABLE;
		}
	}
	return false;
}

void ImGuiManager::update(const Setting& /*setting*/) noexcept
{
	needReloadFont = true;
}

// TODO share code with ImGuiMedia
static std::vector<std::string> getDrives(MSXMotherBoard* motherBoard)
{
	std::vector<std::string> result;
	if (!motherBoard) return result;

	std::string driveName = "diskX";
	auto drivesInUse = RealDrive::getDrivesInUse(*motherBoard);
	for (auto i : xrange(RealDrive::MAX_DRIVES)) {
		if (!(*drivesInUse)[i]) continue;
		driveName[4] = char('a' + i);
		result.push_back(driveName);
	}
	return result;
}

static std::vector<std::string> getSlots(MSXMotherBoard* motherBoard)
{
	std::vector<std::string> result;
	if (!motherBoard) return result;

	const auto& slotManager = motherBoard->getSlotManager();
	std::string cartName = "cartX";
	for (auto slot : xrange(CartridgeSlotManager::MAX_SLOTS)) {
		if (!slotManager.slotExists(slot)) continue;
		cartName[4] = char('a' + slot);
		result.push_back(cartName);
	}
	return result;
}

void ImGuiManager::preNewFrame()
{
	if (!loadIniFile.empty()) {
		ImGui::LoadIniSettingsFromDisk(loadIniFile.c_str());
		loadIniFile.clear();
	}
	if (needReloadFont) {
		needReloadFont = false;
		reloadFont();
	}
}

static bool hoverMenuBar()
{
	const auto* viewport = ImGui::GetMainViewport();
	gl::vec2 topLeft = viewport->Pos;
	gl::vec2 bottomRight = topLeft + gl::vec2(viewport->Size.x, ImGui::GetFrameHeight());
	gl::vec2 mouse = ImGui::GetMousePos();
	return mouse.x >= topLeft.x && mouse.x <= bottomRight.x &&
	       mouse.y >= topLeft.y && mouse.y <= bottomRight.y;
}

void ImGuiManager::paintImGui(bool msxDisplayAreaFocused)
{
	im::ScopedFont sf(fontProp);

	// Apply added/removed parts. Avoids iterating over a changing vector.
	updateParts();

	auto* motherBoard = reactor.getMotherBoard();
	if (motherBoard && !motherBoard->getMachineConfig()) {
		// An empty machine (made by 'create_machine', without a
		// machine loaded in it) has no devices: show it as no machine.
		motherBoard = nullptr;
	}
	for (auto* part : parts) {
		part->paint(motherBoard);
	}
	if (openFile->mustPaint(ImGuiOpenFile::Painter::MANAGER)) {
		openFile->doPaint();
	}

	auto drawMenu = [&]{
		for (auto* part : parts) {
			part->showMenu(motherBoard);
		}
	};
	// FERPECT (macOS): the menus are in the menu bar of the system, and the
	// tool windows are normal windows of the system.
	bool nativeMenu = false;
	if constexpr (mac::NATIVE_UI) {
		if (!nativeMenuInstalled) {
			nativeMenuInstalled = true;
			mac::installMenuBar([this] { return buildNativeMenu(); });
		}
		nativeMenu = !nativeMenuAlsoInWindow;
		ImGuiIO& io = ImGui::GetIO();
		io.ConfigViewportsNoAutoMerge  = nativeToolWindows;
		io.ConfigViewportsNoDecoration = !nativeToolWindows;
		im::nativeWindowTitleBars = nativeToolWindows;
	}
	if (nativeMenu && !mainMenuBarUndocked) {
		// no menu bar inside the window
		bool active = !msxDisplayAreaFocused &&
		              (ImGui::IsWindowHovered(ImGuiHoveredFlags_AnyWindow) ||
		               ImGui::IsWindowFocused(ImGuiHoveredFlags_AnyWindow));
		if (active != guiActive) {
			guiActive = active;
			auto& eventDistributor = reactor.getEventDistributor();
			eventDistributor.distributeEvent(ImGuiActiveEvent(active));
		}
	} else if (mainMenuBarUndocked) {
		im::Window("openMSX main menu", &mainMenuBarUndocked, ImGuiWindowFlags_MenuBar, [&]{
			im::MenuBar([&]{
				if (ImGui::ArrowButton("re-dock-button", ImGuiDir_Down)) {
					mainMenuBarUndocked = false;
				}
				simpleToolTip("Dock the menu bar in the main openMSX window.");
				drawMenu();
			});
		});
	} else {
		bool imGuiActive = !msxDisplayAreaFocused &&
		                  (ImGui::IsWindowHovered(ImGuiHoveredFlags_AnyWindow) ||
		                   ImGui::IsWindowFocused(ImGuiHoveredFlags_AnyWindow));
		bool active = imGuiActive || hoverMenuBar();
		if (active != guiActive) {
			guiActive = active;
			auto& eventDistributor = reactor.getEventDistributor();
			eventDistributor.distributeEvent(ImGuiActiveEvent(active));
		}
		menuAlpha = [&] {
			if (!menuFade) return 1.0f;
			auto target = active ? 1.0f : 0.0f;
			auto period = active ? 0.5f : 5.0f;
			return calculateFade(menuAlpha, target, period);
		}();
		// When the main menu bar gives up the keyboard focus (e.g. after
		// choosing a menu item, or after it took the focus when it first
		// appeared), ImGui gives the focus to the top-most other window.
		// That's never the MSX display area (it stays at the back), but
		// e.g. the console. Instead, give it back to the window that had
		// it before the menu bar took it.
		const auto& g = *ImGui::GetCurrentContext();
		const auto* menuBarWindow = ImGui::FindWindowByName("##MainMenuBar");
		// (not the menus themselves, nor other popups)
		auto isPopup = [](const ImGuiWindow* w) {
			return w->Flags & (ImGuiWindowFlags_Popup | ImGuiWindowFlags_ChildMenu);
		};
		if (g.NavWindow && (g.NavWindow != menuBarWindow) && !isPopup(g.NavWindow)) {
			lastFocusedWindow = g.NavWindow->ID;
		}
		bool menuBarHadFocus = menuBarWindow && (g.NavWindow == menuBarWindow);
		im::StyleVar(ImGuiStyleVar_Alpha, menuAlpha, [&]{
			im::MainMenuBar([&]{
				if (ImGui::ArrowButton("undock-button", ImGuiDir_Up)) {
					mainMenuBarUndocked = true;
				}
				simpleToolTip("Undock the menu bar from the main openMSX window.");
				drawMenu();
			});
		});
		if (menuBarHadFocus && g.NavWindow && (g.NavWindow != menuBarWindow) &&
		    !isPopup(g.NavWindow)) { // e.g. a menu opened via the keyboard
			auto* previous = ImGui::FindWindowByID(lastFocusedWindow);
			if (!previous || !previous->WasActive) {
				// that window was closed: give the focus to the MSX
				previous = ImGui::FindWindowByName("MSX Display Area");
			}
			if (previous && (previous != g.NavWindow)) {
				ImGui::FocusWindow(previous);
			}
		}
	}

	if (statusBarVisible) drawStatusBar(motherBoard);

	// drag and drop  (move this to ImGuiMedia ?)
	auto insert2 = [&](std::string_view displayName, const TclObject& cmd) {
		auto message = strCat("Inserted ", droppedFile, " in ", displayName);
		executeDelayed(cmd, [this, message, cmd](const TclObject&){
			insertedInfo = message;
			openInsertedInfo = true;
			media->addRecent(cmd);
		});
	};
	auto insert = [&](std::string_view displayName, std::string_view cmd) {
		insert2(displayName, makeTclList(cmd, "insert", droppedFile));
	};
	if (handleDropped) {
		handleDropped = false;
		insertedInfo.clear();

		auto category = execute(makeTclList("openmsx_info", "file_type_category", droppedFile))->getString();
		if (category == "unknown" && FileOperations::isDirectory(droppedFile)) {
			category = "disk";
		}

		auto error = [&](auto&& ...message) {
			executeDelayed(makeTclList("error", strCat(message...)));
		};
		auto cantHandle = [&](auto&& ...message) {
			error("Can't handle dropped file ", droppedFile, ": ", message...);
		};
		auto notPresent = [&](const auto& mediaType) {
			cantHandle("no ", mediaType, " present.");
		};

		auto testMedia = [&](std::string_view displayName, std::string_view cmd) {
			if (auto cmdResult = execute(TclObject(cmd))) {
				insert(displayName, cmd);
			} else {
				notPresent(displayName);
			}
		};

		if (category == "disk") {
			auto list = getDrives(motherBoard);
			if (list.empty()) {
				notPresent("disk drive");
			} else if (list.size() == 1) {
				const auto& drive = list.front();
				insert(strCat("disk drive ", char(drive.back() - 'a' + 'A')), drive);
			} else {
				selectList = std::move(list);
				ImGui::OpenPopup("select-drive");
			}
		} else if (category == "rom") {
			auto list = getSlots(motherBoard);
			if (list.empty()) {
				notPresent("cartridge slot");
				return;
			}
			selectedMedia = list.front();
			selectList = std::move(list);
			if (auto sha1 = reactor.getFilePool().getSha1Sum(droppedFile)) {
				romInfo = reactor.getSoftwareDatabase().fetchRomInfo(*sha1);
			} else {
				romInfo = nullptr;
			}
			selectedRomType = romInfo ? romInfo->getRomType()
			                          : RomType::UNKNOWN; // auto-detect
			ImGui::OpenPopup("select-cart");
		} else if (category == "cassette") {
			testMedia("casette port", "cassetteplayer");
		} else if (category == "laserdisc") {
			testMedia("laser disc player", "laserdiscplayer");
		} else if (category == "savestate") {
			executeDelayed(makeTclList("loadstate", droppedFile));
		} else if (category == "replay") {
			executeDelayed(makeTclList("reverse", "loadreplay", droppedFile));
		} else if (category == "script") {
			executeDelayed(makeTclList("source", droppedFile));
		} else if (FileOperations::getExtension(droppedFile) == ".txt") {
			executeDelayed(makeTclList("type_from_file", droppedFile));
		} else {
			cantHandle("unknown file type");
		}
	}
	im::Popup("select-drive", [&]{
		ImGui::TextUnformatted(tmpStrCat("Select disk drive for ", droppedFile));
		auto n = std::min(3.5f, narrow<float>(selectList.size()));
		auto height = n * ImGui::GetTextLineHeightWithSpacing() + ImGui::GetStyle().FramePadding.y;
		im::ListBox("##select-media", {-FLT_MIN, height}, [&]{
			for (const auto& item : selectList) {
				auto drive = item.back() - 'a';
				auto display = strCat(char('A' + drive), ": ", media->displayNameForDriveContent(drive, true));
				if (ImGui::Selectable(display.c_str())) {
					insert(strCat("disk drive ", char(drive + 'A')), item);
					ImGui::CloseCurrentPopup();
				}
			}
		});
	});
	im::Popup("select-cart", [&]{
		ImGui::TextUnformatted(strCat("Filename: ", droppedFile));
		ImGui::Separator();

		if (!romInfo) {
			ImGui::TextUnformatted("ROM not present in software database"sv);
		}
		im::Table("##extension-info", 2, [&]{
			const char* buf = reactor.getSoftwareDatabase().getBufferStart();
			ImGui::TableSetupColumn("description", ImGuiTableColumnFlags_WidthFixed);
			ImGui::TableSetupColumn("value", ImGuiTableColumnFlags_WidthStretch);

			if (romInfo) {
				ImGuiMedia::printDatabase(*romInfo, buf);
			}
			if (ImGui::TableNextColumn()) {
				ImGui::AlignTextToFramePadding();
				ImGui::TextUnformatted("Mapper"sv);
			}
			if (ImGui::TableNextColumn()) {
				ImGuiMedia::selectMapperType("##mapper-type", selectedRomType);
			}
		});
		ImGui::Separator();

		if (selectList.size() > 1) {
			const auto& slotManager = motherBoard->getSlotManager();
			ImGui::TextUnformatted("Select cartridge slot"sv);
			auto n = std::min(3.5f, narrow<float>(selectList.size()));
			auto height = n * ImGui::GetTextLineHeightWithSpacing() + ImGui::GetStyle().FramePadding.y;
			im::ListBox("##select-media", {-FLT_MIN, height}, [&]{
				for (const auto& item : selectList) {
					auto slot = item.back() - 'a';
					auto display = strCat(
						char('A' + slot),
						" (", slotManager.getPsSsString(slot), "): ",
						media->displayNameForSlotContent(slotManager, slot, true));

					if (ImGui::Selectable(display.c_str(), item == selectedMedia)) {
						selectedMedia = item;
					}
				}
			});
		}

		ImGui::Checkbox("Reset MSX on inserting ROM", &media->resetOnCartChanges);

		if (ImGui::Button("Insert ROM")) {
			auto cmd = makeTclList(selectedMedia, "insert", droppedFile);
			if (selectedRomType != RomType::UNKNOWN) {
				cmd.addListElement("-romtype", RomInfo::romTypeToName(selectedRomType));
			}
			insert2(strCat("cartridge slot ", char(selectedMedia.back() - 'a' + 'A')), cmd);
			if (media->resetOnCartChanges) {
				executeDelayed(TclObject("reset"));
			}
			ImGui::CloseCurrentPopup();
		}
		ImGui::SameLine();
		if (ImGui::Button("Cancel")) {
			ImGui::CloseCurrentPopup();
		}
	});
	if (openInsertedInfo) {
		openInsertedInfo = false;
		insertedInfoTimeout = 3.0f;
		ImGui::OpenPopup("inserted-info");
	}
	im::Popup("inserted-info", [&]{
		insertedInfoTimeout -= ImGui::GetIO().DeltaTime;
		if (insertedInfoTimeout <= 0.0f || insertedInfo.empty()) {
			ImGui::CloseCurrentPopup();
		}
		im::TextWrapPos(ImGui::GetFontSize() * 35.0f, [&]{
			ImGui::TextUnformatted(insertedInfo);
		});
	});
}

void ImGuiManager::drawStatusBar(MSXMotherBoard* motherBoard)
{
	ImGuiWindowFlags flags =
		ImGuiWindowFlags_NoScrollbar |
		ImGuiWindowFlags_NoSavedSettings |
		ImGuiWindowFlags_MenuBar |
		ImGuiWindowFlags_NoFocusOnAppearing;
	if (ImGui::BeginViewportSideBar("##MainStatusBar", nullptr, ImGuiDir_Down, ImGui::GetFrameHeight(), flags)) {
		im::MenuBar([&]{
			auto pos = ImGui::GetCursorPos();

			auto frameTime = ImGui::GetIO().DeltaTime;

			if (statusBarItemVisibilityFps) {
				// limit updating to at most 10Hz
				fpsDrawTimeOut -= frameTime;
				if (fpsDrawTimeOut < 0.0f) {
					fpsDrawTimeOut = 0.1f;
					fps = reactor.getDisplay().getFps();
				}
				std::array<char, 32> buf;
				auto fpsStr = format_to_buf(buf, "{:.1f} fps", fps);
				ImGui::RightAlignText(fpsStr, "999.9 fps");
				simpleToolTip("refresh rate");
				ImGui::Separator();
			}

			if (statusBarItemVisibilityScreenModeInfo) {
				auto [modeStr, extendedStr] = [&] { // TODO: remove duplication with VDP debugger code
					if (!motherBoard) return std::pair{"-", ""};
					const auto* vdp = dynamic_cast<const VDP*>(motherBoard->findDevice("VDP"));
					if (!vdp) return std::pair{"-", ""};

					auto mode = vdp->getDisplayMode();
					auto base = mode.getBase();
					if (base == DisplayMode::TEXT1)      return std::pair{"0 (40)", "TEXT 1"};
					if (base == DisplayMode::TEXT2)      return std::pair{"0 (80)", "TEXT 2"};
					if (base == DisplayMode::GRAPHIC1)   return std::pair{"1", "GRAPHIC 1"};
					if (base == DisplayMode::GRAPHIC2)   return std::pair{"2", "GRAPHIC 2"};
					if (base == DisplayMode::GRAPHIC3)   return std::pair{"4", "GRAPHIC 3"};
					if (base == DisplayMode::MULTICOLOR) return std::pair{"3", "MULTICOLOR"};
					if (base == DisplayMode::GRAPHIC4)   return std::pair{"5", "GRAPHIC 4"};
					if (base == DisplayMode::GRAPHIC5)   return std::pair{"6", "GRAPHIC 5"};
					if (base == DisplayMode::GRAPHIC6)   return std::pair{"7", "GRAPHIC 6"};
					if (base != DisplayMode::GRAPHIC7)   return std::pair{"?", ""};
					return (mode.getByte() & DisplayMode::YJK)
						? (mode.getByte() & DisplayMode::YAE) ? std::pair{"11", "GRAPHIC 7 (YJK/YAE mode)"} : std::pair{"12", "GRAPHIC 7 (YJK mode)"}
						: std::pair{"8", "GRAPHIC 7"};
				}();
				ImGui::RightAlignText(modeStr, "0 (80)");
				simpleToolTip([&]{
					return tmpStrCat(
						"screen mode as used in MSX-BASIC",
						strCat_if(extendedStr[0], ", corresponds to VDP mode ", extendedStr));
				});
				ImGui::Separator();
			}

			if (statusBarItemVisibilityTime) {
				auto timeStr = motherBoard
					? formatTime(motherBoard->getCurrentTime().toDouble())
					: formatTime(std::nullopt);
				ImGui::RightAlignText(timeStr, formatTime(0));
				simpleToolTip("time since MSX power on");
				ImGui::Separator();
			}

			if (statusBarItemVisibilityActualSpeed) {
				if (motherBoard) {
					// limit updating to at most 1Hz
					speedDrawTimeOut -= frameTime;
					if (speedDrawTimeOut < 0.0f) {
						auto realTimePassed = 1.0f - speedDrawTimeOut;
						speedDrawTimeOut = 1.0f;

						auto boardTime = motherBoard->getCurrentTime();
						auto boardTimePassed = (boardTime < prevBoardTime)
							? 0.0 // due to reverse for instance
							: (boardTime - prevBoardTime).toDouble();
						prevBoardTime = boardTime;

						speed = 100.0f * float(boardTimePassed) / realTimePassed;
					}
				} else {
					speed = 0.0f;
					prevBoardTime = EmuTime::zero();
				}
				ImGui::RightAlignText(strCat(std::lrint(speed), '%'), "10000%");
				simpleToolTip("emulation speed");
				ImGui::Separator();
			}

			if (statusBarItemVisibilityMachine) {
				if (motherBoard) {
					if (const HardwareConfig* machineConfig = motherBoard->getMachineConfig()) {
						if (const auto* info = machineConfig->getConfig().findChild("info")) {
							auto manuf = info->getChildData("manufacturer", "?");
							auto code  = info->getChildData("code", "?");
							ImGui::StrCat(manuf, ' ', code);
							simpleToolTip([&]{
								auto type  = info->getChildData("type", "");
								auto desc = info->getChildData("description", "");
								return strCat((type.empty() ? "" : strCat("Machine type: ", type, '\n')), desc);
							});
						}
					}
				}
				ImGui::Separator();
			}

			if (statusBarItemVisibilityRunningSoftware) {
				if (auto result = execute(TclObject("guess_title"))) {
					ImGui::TextUnformatted(result->getString());
					simpleToolTip("the (probably) currently running software");
					if (auto mapperResult = execute(TclObject("dict get [openmsx_info romtype [dict get [machine_info device [guess_rom_device]] \"mappertype\"]] description"))) {
						ImGui::TextUnformatted(strCat(" (", mapperResult->getString(), ")"));
						simpleToolTip("the mapper type of the running ROM software");
					};
				}
			}

			ImGui::SetCursorPos(pos);
			ImGui::Dummy(ImGui::GetContentRegionAvail());
			im::PopupContextItem("status bar context menu", [&]{
				configStatusBarVisibilityItems();
			});
		});
	}
	ImGui::End();
}

void ImGuiManager::configStatusBarVisibilityItems()
{
	ImGui::Checkbox("Show FPS indicator", &statusBarItemVisibilityFps);
	ImGui::Checkbox("Show screen mode info", &statusBarItemVisibilityScreenModeInfo);
	ImGui::Checkbox("Show machine time", &statusBarItemVisibilityTime);
	ImGui::Checkbox("Show actual emulation speed", &statusBarItemVisibilityActualSpeed);
	ImGui::Checkbox("Show machine name info", &statusBarItemVisibilityMachine);
	ImGui::Checkbox("Show running software", &statusBarItemVisibilityRunningSoftware);
}

void ImGuiManager::iniReadInit()
{
	updateParts();
	for (auto* part : parts) {
		if (part) { // loadStart() could call unregisterPart()
			part->loadStart();
		}
	}
}

void* ImGuiManager::iniReadOpen(std::string_view name)
{
	updateParts();
	for (auto* part : parts) {
		if (part->iniName() == name) return part;
	}
	return nullptr;
}

void ImGuiManager::loadLine(void* entry, const char* line_) const
{
	zstring_view line = line_;
	auto pos = line.find('=');
	if (pos == zstring_view::npos) return;
	std::string_view name = line.substr(0, pos);
	zstring_view value = line.substr(pos + 1);

	assert(entry);
	static_cast<ImGuiPartInterface*>(entry)->loadLine(name, value);
}

void ImGuiManager::iniApplyAll()
{
	updateParts();
	for (auto* part : parts) {
		part->loadEnd();
	}
}

void ImGuiManager::iniWriteAll(ImGuiTextBuffer& buf)
{
	updateParts();
	for (auto* part : parts) {
		if (auto name = part->iniName(); !name.empty()) {
			buf.appendf("[openmsx][%s]\n", name.c_str());
			part->save(buf);
			buf.append("\n");
		}
	}
}


// FERPECT: the menus for the menu bar of the operating system (macOS).
//
// This mirrors the most used items of the showMenu() methods of the parts.
// Things that are not here are still in the openMSX menu bar, that can be
// shown inside the window from the 'View' menu.
//
// The actions run later, from the openMSX main loop (executeDelayed()): the
// menu calls us from inside the event handling of the operating system.
// FERPECT: text of the native menus, in the language of the system or in the
// one chosen in the 'Settings' menu (the rest of openMSX is in English).
std::string ImGuiManager::nativeTr(std::string_view english) const
{
	switch (nativeMenuLanguage) {
	case 1:  return std::string(english);
	case 2:  return mac::tr(english, "es");
	default: return mac::tr(english);
	}
}

std::vector<NativeMenuItem> ImGuiManager::buildNativeMenu()
{
	using Item = NativeMenuItem;
	using S = NativeMenuItem::Standard;
	auto T = [this](std::string_view english) { return nativeTr(english); };

	auto* motherBoard = reactor.getMotherBoard();
	if (motherBoard && !motherBoard->getMachineConfig()) motherBoard = nullptr;
	bool hasMachine = motherBoard != nullptr;

	auto separator = [] {
		Item it;
		it.standard = S::SEPARATOR;
		return it;
	};
	auto standard = [&](S kind, std::string_view title, std::string key = {}, unsigned mods = Item::CMD) {
		Item it;
		it.standard = kind;
		it.title = T(title);
		it.key = std::move(key);
		it.mods = mods;
		return it;
	};
	auto item = [&](std::string_view title, std::function<void()> action,
	                std::string key = {}, unsigned mods = Item::CMD) {
		Item it;
		it.title = T(title);
		it.key = std::move(key);
		it.mods = mods;
		it.action = [this, action = std::move(action)] { executeDelayed(action); };
		return it;
	};
	auto command = [&](std::string_view title, std::string_view cmd,
	                   std::string key = {}, unsigned mods = Item::CMD) {
		return item(title, [this, c = std::string(cmd)] {
			executeDelayed(TclObject(c));
		}, std::move(key), mods);
	};
	// a window (or other thing) that is shown when 'flag' is true
	auto toggle = [&](std::string_view title, bool* flag,
	                  std::string key = {}, unsigned mods = Item::CMD) {
		auto it = item(title, [flag] { if (flag) *flag = !*flag; }, std::move(key), mods);
		it.checked = flag && *flag;
		it.enabled = flag != nullptr;
		return it;
	};
	auto settingIsOn = [&](std::string_view name) {
		auto result = execute(makeTclList("set", name));
		if (!result) return false;
		return result->getOptionalBool().value_or(false);
	};
	// a boolean openMSX setting
	auto setting = [&](std::string_view title, std::string_view name,
	                   std::string key = {}, unsigned mods = Item::CMD) {
		auto it = command(title, tmpStrCat("toggle ", name), std::move(key), mods);
		it.checked = settingIsOn(name);
		return it;
	};
	auto submenu = [&](std::string_view title, std::vector<Item> children, bool enabled = true) {
		Item it;
		it.title = T(title);
		it.children = std::move(children);
		it.enabled = enabled;
		return it;
	};
	auto disableWithoutMachine = [&](Item it) {
		if (!hasMachine) it.enabled = false;
		return it;
	};
	auto insertFromPanel = [this](std::string media, std::string title) {
		executeDelayed([this, media, title] {
			auto file = mac::runOpenPanel(title, {}, false, {});
			if (!file) return;
			auto cmd = makeTclList(media, "insert", *file);
			executeDelayed(cmd, [this, cmd](const TclObject&) {
				this->media->addRecent(cmd);
			});
		});
	};

	std::vector<Item> bar;

	// --- application menu
	{
		std::vector<Item> m;
		m.push_back(item("About openMSX", [] {
			mac::showAbout(std::string(std::string_view(Version::full())));
		}));
		m.push_back(separator());
		m.push_back(standard(S::SERVICES, "Services"));
		m.push_back(separator());
		m.push_back(standard(S::HIDE, "Hide openMSX", "h"));
		m.push_back(standard(S::HIDE_OTHERS, "Hide Others", "h", Item::CMD | Item::ALT));
		m.push_back(standard(S::SHOW_ALL, "Show All"));
		m.push_back(separator());
		m.push_back(standard(S::QUIT, "Quit openMSX", "q"));
		auto top = submenu("openMSX", std::move(m));
		top.role = Item::Role::APP;
		bar.push_back(std::move(top));
	}

	// --- File
	{
		std::vector<Item> m;
		m.push_back(item("Open...", [this] {
			if (auto file = mac::runOpenPanel(nativeTr("Open a cartridge, disk, cassette or other file"), {}, false, {})) {
				// same as a file dropped on the window
				droppedFile = *file;
				handleDropped = true;
			}
		}, "o"));
		m.push_back(separator());
		for (const auto& slot : getSlots(motherBoard)) {
			auto index = size_t(slot.back() - 'a');
			auto letter = std::string(1, char('A' + index));
			std::vector<Item> sub;
			sub.push_back(item("Insert...", [this, insertFromPanel, slot] {
				insertFromPanel(slot, nativeTr("Insert a cartridge"));
			}));
			sub.push_back(command("Eject", tmpStrCat(slot, " eject")));
			sub.push_back(separator());
			sub.push_back(toggle("More Options...", &media->cartridgeMediaInfo[index].show));
			Item it;
			it.title = strCat(T("Cartridge Slot"), ' ', letter);
			it.children = std::move(sub);
			m.push_back(std::move(it));
		}
		for (const auto& drive : getDrives(motherBoard)) {
			auto index = size_t(drive.back() - 'a');
			auto letter = std::string(1, char('A' + index));
			std::vector<Item> sub;
			sub.push_back(item("Insert...", [this, insertFromPanel, drive] {
				insertFromPanel(drive, nativeTr("Insert a disk"));
			}));
			sub.push_back(command("Eject", tmpStrCat(drive, " eject")));
			sub.push_back(separator());
			sub.push_back(toggle("More Options...", &media->diskMediaInfo[index].show));
			Item it;
			it.title = strCat(T("Disk Drive"), ' ', letter);
			it.children = std::move(sub);
			m.push_back(std::move(it));
		}
		if (hasMachine && execute(TclObject("cassetteplayer"))) {
			std::vector<Item> sub;
			sub.push_back(item("Insert...", [this, insertFromPanel] {
				insertFromPanel("cassetteplayer", nativeTr("Insert a cassette"));
			}));
			sub.push_back(command("Eject", "cassetteplayer eject"));
			sub.push_back(command("Rewind", "cassetteplayer rewind"));
			sub.push_back(separator());
			sub.push_back(toggle("Tape Deck...", &media->cassetteMediaInfo.show));
			m.push_back(submenu("Cassette", std::move(sub)));
		}
		m.push_back(separator());
		m.push_back(disableWithoutMachine(command("Quick Load State", "loadstate")));
		m.push_back(disableWithoutMachine(command("Quick Save State", "savestate")));
		m.push_back(disableWithoutMachine(item("Load State...", [this] {
			auto dir = FileOperations::getUserOpenMSXDir("savestates");
			if (auto file = mac::runOpenPanel(nativeTr("Load a saved state"), {}, false, dir)) {
				executeDelayed(makeTclList("loadstate", *file));
			}
		})));
		m.push_back(separator());
		m.push_back(disableWithoutMachine(command("Save Screenshot", "screenshot -guess-name", "d")));
		m.push_back(toggle("Screenshot Options...", &tools->showScreenshot));
		m.push_back(toggle("Record Audio/Video...", &tools->showRecord));
		m.push_back(separator());
		m.push_back(standard(S::CLOSE, "Close", "w"));
		bar.push_back(submenu("File", std::move(m)));
	}

	// --- Edit
	{
		std::vector<Item> m;
		m.push_back(disableWithoutMachine(command("Copy Screen Text", "copy_screen_to_clipboard",
		                                          "c", Item::CMD | Item::SHIFT)));
		m.push_back(disableWithoutMachine(command("Paste into the MSX", "type_clipboard",
		                                          "v", Item::CMD | Item::SHIFT)));
		bar.push_back(submenu("Edit", std::move(m)));
	}

	// --- Machine
	{
		std::vector<Item> m;
		m.push_back(setting("Pause", "pause", "p"));
		m.push_back(disableWithoutMachine(command("Reset", "reset", "r")));
		m.push_back(setting("Power", "power"));
		m.push_back(separator());
		{
			auto it = command("Full Speed", "toggle throttle");
			it.checked = !settingIsOn("throttle");
			m.push_back(std::move(it));
		}
		m.push_back(setting("Fast Forward", "fastforward", "t"));
		m.push_back(setting("Full Speed When Loading", "fullspeedwhenloading"));
		m.push_back(separator());
		m.push_back(toggle("Select MSX Machine...", &machine->showSelectMachine));
		m.push_back(toggle("Test MSX Hardware...", &machine->showTestHardware));
		m.push_back(separator());
		m.push_back(disableWithoutMachine(toggle("Reverse Bar", &reverseBar->showReverseBar)));
		bar.push_back(submenu("Machine", std::move(m)));
	}

	// --- View
	{
		std::vector<Item> m;
		m.push_back(setting("Full Screen", "fullscreen", "f", Item::CMD | Item::CTRL));
		m.push_back(separator());
		int scale = 0;
		if (auto r = execute(TclObject("set scale_factor"))) {
			scale = r->getOptionalInt().value_or(0);
		}
		for (int i = 1; i <= 4; ++i) {
			static constexpr std::array<std::string_view, 4> names = {
				"Normal Size (x1)", "Double Size (x2)", "Triple Size (x3)", "Quadruple Size (x4)",
			};
			auto it = command(names[i - 1], tmpStrCat("set scale_factor ", i),
			                  std::string(1, char('0' + i)), Item::CMD | Item::ALT);
			it.checked = scale == i;
			m.push_back(std::move(it));
		}
		m.push_back(separator());
		m.push_back(setting("PAL TV Proportions", "pal_aspect"));
		m.push_back(setting("Full Stretch", "full_stretch"));
		m.push_back(setting("Deinterlace", "deinterlace"));
		m.push_back(setting("Deflicker", "deflicker"));
		m.push_back(setting("VSync", "vsync"));
		m.push_back(separator());
		m.push_back(toggle("Status Bar", &statusBarVisible));
		m.push_back(toggle("Tool Windows as Mac Windows", &nativeToolWindows));
		m.push_back(toggle("openMSX Menu Bar in the Window", &nativeMenuAlsoInWindow, ","));
		bar.push_back(submenu("View", std::move(m)));
	}

	// --- Settings
	{
		std::vector<Item> m;
		m.push_back(setting("Mute", "mute", "u"));
		m.push_back(toggle("Sound Chip Settings...", &soundChip->showSoundChipSettings));
		m.push_back(separator());
		m.push_back(setting("Grab Input", "grabinput"));
		m.push_back(toggle("Configure MSX Joysticks...", &settings->showConfigureJoystick));
		m.push_back(toggle("Edit Shortcuts...", &settings->showShortcut));
		m.push_back(separator());
		m.push_back(toggle("Select Font...", &settings->showFont));
		m.push_back(toggle("Configure OSD Icons...", &osdIcons->showConfigureIcons));
		m.push_back(toggle("Configure Messages...", &messages->configureWindow.open));
		m.push_back(separator());
		{
			std::vector<Item> sub;
			static constexpr std::array<std::string_view, 3> names = {
				"System Default", "English", "Spanish",
			};
			for (int i = 0; i < 3; ++i) {
				auto it = item(names[i], [this, i] {
					nativeMenuLanguage = i;
					nativeMenuInstalled = false; // build the whole menu bar again
				});
				it.checked = nativeMenuLanguage == i;
				sub.push_back(std::move(it));
			}
			m.push_back(submenu("Menu Language", std::move(sub)));
		}
		bar.push_back(submenu("Settings", std::move(m)));
	}

	// --- Tools
	{
		std::vector<Item> m;
		m.push_back(toggle("Console", &console->show, "l"));
		m.push_back(toggle("Virtual Keyboard", &keyboard->show));
		m.push_back(toggle("Message Log", &messages->logWindow.open));
		m.push_back(separator());
		m.push_back(toggle("Disk Manipulator", &diskManipulator->show));
		m.push_back(separator());
		m.push_back(toggle("Trainer Selector", &trainer->show));
		m.push_back(toggle("Cheat Finder", &cheatFinder->show));
		m.push_back(separator());
		m.push_back(toggle("SCC Viewer", &sccViewer->show));
		m.push_back(toggle("MSX-Music Viewer", &msxMusicViewer->show));
		m.push_back(toggle("Audio Channel Viewer", &waveViewer->show));
		m.push_back(toggle("Plotter Viewer", &plotterViewer->show));
		m.push_back(separator());
		m.push_back(toggle("Slot Map", &slotMap->show));
		m.push_back(toggle("I/O Ports", &ioPorts->show));
		bar.push_back(submenu("Tools", std::move(m)));
	}

	// --- Debugger
	{
		std::vector<Item> m;
		auto open = [&](std::string_view title, std::string what) {
			return item(title, [this, what] { debugger->nativeMenuOpen(what); });
		};
		m.push_back(toggle("Tool Bar", debugger->nativeMenuFlag("control")));
		m.push_back(open("Disassembly", "disassembly"));
		m.push_back(toggle("CPU Registers", debugger->nativeMenuFlag("registers")));
		m.push_back(toggle("CPU Flags", debugger->nativeMenuFlag("flags")));
		m.push_back(toggle("Slots", debugger->nativeMenuFlag("slots")));
		m.push_back(toggle("Stack", debugger->nativeMenuFlag("stack")));
		m.push_back(open("Memory", "memory"));
		m.push_back(separator());
		m.push_back(toggle("Breakpoints", &breakPoints->show));
		m.push_back(toggle("Symbol Manager", &symbols->show));
		m.push_back(toggle("Watch Expression", &watchExpr->show));
		m.push_back(toggle("Probe/Trace Viewer", &traceViewer->show));
		m.push_back(separator());
		m.push_back(open("VDP Bitmap Viewer", "bitmap"));
		m.push_back(open("VDP Tile Viewer", "tile"));
		m.push_back(open("VDP Sprite Viewer", "sprite"));
		m.push_back(toggle("Raster Beam Viewer", &rasterViewer->show));
		m.push_back(toggle("VDP Register Viewer", &vdpRegs->show));
		m.push_back(toggle("Palette Editor", &palette->window.open));
		if (!hasMachine) {
			for (auto& it : m) it.enabled = false;
		}
		bar.push_back(submenu("Debugger", std::move(m)));
	}

	// --- Window
	{
		std::vector<Item> m;
		m.push_back(standard(S::MINIMIZE, "Minimize", "m"));
		m.push_back(standard(S::ZOOM, "Zoom"));
		m.push_back(separator());
		m.push_back(standard(S::BRING_ALL_TO_FRONT, "Bring All to Front"));
		auto top = submenu("Window", std::move(m));
		top.role = Item::Role::WINDOW;
		bar.push_back(std::move(top));
	}

	// --- Help
	{
		std::vector<Item> m;
		auto manual = [&](std::string_view title, std::string_view page) {
			return item(title, [page = std::string(page)] {
				SDL_OpenURL(strCat("file://", FileOperations::getSystemDocDir(),
				                   "/manual/", page).c_str());
			});
		};
		m.push_back(manual("FAQ", "faq.html"));
		m.push_back(manual("Setup Guide", "setup.html"));
		m.push_back(manual("User Manual", "user.html"));
		m.push_back(separator());
		m.push_back(toggle("About openMSX (credits)", &help->showAboutOpenMSX));
		auto top = submenu("Help", std::move(m));
		top.role = Item::Role::HELP;
		bar.push_back(std::move(top));
	}

	return bar;
}

} // namespace openmsx
