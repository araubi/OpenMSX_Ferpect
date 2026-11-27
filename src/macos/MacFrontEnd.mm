// FERPECT: native macOS user interface, see MacFrontEnd.hh.

#include "MacFrontEnd.hh"

#import <Cocoa/Cocoa.h>

#include <SDL3/SDL.h>

using openmsx::NativeMenuItem;

@interface FerpectMenuController : NSObject <NSMenuDelegate>
- (void)itemChosen:(id)sender;
@end

static std::function<std::vector<NativeMenuItem>()> menuBuilder;
static std::vector<NativeMenuItem> menuModel;
static CFAbsoluteTime menuModelTime = 0;
static FerpectMenuController* menuController = nil;

static NSString* toNS(const std::string& s)
{
	NSString* result = [NSString stringWithUTF8String:s.c_str()];
	return result ? result : @"";
}

// The description of the menus. Building it is cheap, but when macOS looks
// for a key equivalent it asks every menu in a row: reuse it for a moment.
static const std::vector<NativeMenuItem>& currentModel()
{
	CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
	if (menuModel.empty() || ((now - menuModelTime) > 0.2)) {
		if (menuBuilder) menuModel = menuBuilder();
		menuModelTime = now;
	}
	return menuModel;
}

static void fillMenu(NSMenu* menu, const std::vector<NativeMenuItem>& items);

static NSMenuItem* makeItem(const NativeMenuItem& it)
{
	using S = NativeMenuItem::Standard;
	if (it.standard == S::SEPARATOR) {
		return [NSMenuItem separatorItem];
	}

	SEL sel = nil;
	id target = nil;
	switch (it.standard) {
	case S::HIDE:        sel = @selector(hide:);                   target = NSApp; break;
	case S::HIDE_OTHERS: sel = @selector(hideOtherApplications:);  target = NSApp; break;
	case S::SHOW_ALL:    sel = @selector(unhideAllApplications:);  target = NSApp; break;
	case S::QUIT:        sel = @selector(terminate:);              target = NSApp; break;
	case S::BRING_ALL_TO_FRONT: sel = @selector(arrangeInFront:);  target = NSApp; break;
	case S::MINIMIZE:    sel = @selector(performMiniaturize:);     break; // to the key window
	case S::ZOOM:        sel = @selector(performZoom:);            break;
	case S::CLOSE:       sel = @selector(performClose:);           break;
	case S::SERVICES:    break;
	default:             sel = @selector(itemChosen:);             target = menuController; break;
	}

	NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:toNS(it.title)
	                                              action:sel
	                                       keyEquivalent:toNS(it.key)];
	if (!it.key.empty()) {
		NSEventModifierFlags flags = 0;
		if (it.mods & NativeMenuItem::CMD)   flags |= NSEventModifierFlagCommand;
		if (it.mods & NativeMenuItem::SHIFT) flags |= NSEventModifierFlagShift;
		if (it.mods & NativeMenuItem::ALT)   flags |= NSEventModifierFlagOption;
		if (it.mods & NativeMenuItem::CTRL)  flags |= NSEventModifierFlagControl;
		item.keyEquivalentModifierMask = flags;
	}
	item.target = target;

	if (it.standard == S::SERVICES) {
		NSMenu* services = [[NSMenu alloc] initWithTitle:toNS(it.title)];
		item.submenu = services;
		NSApp.servicesMenu = services;
	} else if (!it.children.empty()) {
		NSMenu* sub = [[NSMenu alloc] initWithTitle:toNS(it.title)];
		sub.autoenablesItems = NO;
		fillMenu(sub, it.children);
		item.submenu = sub;
		item.action = nil;
		item.target = nil;
		item.enabled = it.enabled ? YES : NO;
	} else if (it.standard == S::NONE) {
		std::function<void()> action = it.action;
		item.representedObject = [^{ if (action) action(); } copy];
		item.enabled = (it.enabled && it.action) ? YES : NO;
		item.state = it.checked ? NSControlStateValueOn : NSControlStateValueOff;
	}
	return item;
}

static void fillMenu(NSMenu* menu, const std::vector<NativeMenuItem>& items)
{
	for (const auto& it : items) {
		[menu addItem:makeItem(it)];
	}
}

@implementation FerpectMenuController

- (void)itemChosen:(id)sender
{
	id object = [sender representedObject];
	if (object) {
		void (^block)(void) = object;
		block();
	}
}

// A top-level menu is about to be shown, or macOS looks for a key
// equivalent in it: fill it again from the current state.
- (void)menuNeedsUpdate:(NSMenu*)menu
{
	NSInteger index = [NSApp.mainMenu indexOfItemWithSubmenu:menu];
	const auto& model = currentModel();
	if ((index < 0) || (size_t(index) >= model.size())) return;
	[menu removeAllItems];
	fillMenu(menu, model[size_t(index)].children);
}

@end

namespace openmsx::mac {

void installMenuBar(std::function<std::vector<NativeMenuItem>()> builder)
{
	@autoreleasepool {
		menuBuilder = std::move(builder);
		menuModel.clear();
		if (!menuController) {
			menuController = [[FerpectMenuController alloc] init];
		}
		// no "Show Tab Bar" etc. in our menus
		NSWindow.allowsAutomaticWindowTabbing = NO;

		NSMenu* bar = [[NSMenu alloc] initWithTitle:@""];
		for (const auto& top : currentModel()) {
			NSMenuItem* topItem = [[NSMenuItem alloc] initWithTitle:toNS(top.title)
			                                                 action:nil
			                                          keyEquivalent:@""];
			NSMenu* menu = [[NSMenu alloc] initWithTitle:toNS(top.title)];
			menu.autoenablesItems = NO;
			fillMenu(menu, top.children);
			topItem.submenu = menu;
			[bar addItem:topItem];
			switch (top.role) {
			case NativeMenuItem::Role::WINDOW:
				// macOS itself adds the list of windows here
				NSApp.windowsMenu = menu;
				break;
			case NativeMenuItem::Role::HELP:
				NSApp.helpMenu = menu;
				break;
			case NativeMenuItem::Role::APP:
				break;
			default:
				menu.delegate = menuController;
				break;
			}
		}
		NSApp.mainMenu = bar;
	}
}

void configureMainWindow(SDL_Window* window)
{
	@autoreleasepool {
		if (!window) return;
		void* p = SDL_GetPointerProperty(SDL_GetWindowProperties(window),
		                                 SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, nullptr);
		if (!p) return;
		NSWindow* nsWindow = (__bridge NSWindow*)p;
		nsWindow.tabbingMode = NSWindowTabbingModeDisallowed;
		// the green button puts the window in full screen, in its own Space
		nsWindow.collectionBehavior |= NSWindowCollectionBehaviorFullScreenPrimary;
	}
}

static NSArray<NSString*>* toTypes(const std::vector<std::string>& extensions)
{
	NSMutableArray<NSString*>* result = [NSMutableArray array];
	for (const auto& e : extensions) {
		if (!e.empty()) [result addObject:toNS(e)];
	}
	return result;
}

std::optional<std::string> runOpenPanel(
	const std::string& title, const std::vector<std::string>& extensions,
	bool chooseDirectory, const std::string& startDir)
{
	@autoreleasepool {
		NSOpenPanel* panel = [NSOpenPanel openPanel];
		panel.message = toNS(title);
		panel.canChooseFiles = chooseDirectory ? NO : YES;
		panel.canChooseDirectories = chooseDirectory ? YES : NO;
		panel.allowsMultipleSelection = NO;
		panel.resolvesAliases = YES;
		if (!startDir.empty()) {
			panel.directoryURL = [NSURL fileURLWithPath:toNS(startDir) isDirectory:YES];
		}
		if (!chooseDirectory && !extensions.empty()) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
			panel.allowedFileTypes = toTypes(extensions);
#pragma clang diagnostic pop
		}
		if ([panel runModal] != NSModalResponseOK) return {};
		NSURL* url = panel.URL;
		if (!url || !url.fileSystemRepresentation) return {};
		return std::string(url.fileSystemRepresentation);
	}
}

std::optional<std::string> runSavePanel(
	const std::string& title, const std::vector<std::string>& extensions,
	const std::string& startDir)
{
	@autoreleasepool {
		NSSavePanel* panel = [NSSavePanel savePanel];
		panel.message = toNS(title);
		panel.canCreateDirectories = YES;
		if (!startDir.empty()) {
			panel.directoryURL = [NSURL fileURLWithPath:toNS(startDir) isDirectory:YES];
		}
		if (!extensions.empty()) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
			panel.allowedFileTypes = toTypes(extensions);
#pragma clang diagnostic pop
			panel.allowsOtherFileTypes = YES;
		}
		if ([panel runModal] != NSModalResponseOK) return {};
		NSURL* url = panel.URL;
		if (!url || !url.fileSystemRepresentation) return {};
		return std::string(url.fileSystemRepresentation);
	}
}

void showAbout(const std::string& version)
{
	@autoreleasepool {
		NSDictionary* options = @{
			@"ApplicationName": @"openMSX FERPECT",
			@"ApplicationVersion": toNS(version),
			@"Version": @"",
		};
		[NSApp orderFrontStandardAboutPanelWithOptions:options];
		[NSApp activateIgnoringOtherApps:YES];
	}
}

void openURL(const std::string& url)
{
	@autoreleasepool {
		NSURL* nsUrl = [NSURL URLWithString:toNS(url)];
		if (!nsUrl) {
			nsUrl = [NSURL fileURLWithPath:toNS(url)];
		}
		if (nsUrl) [[NSWorkspace sharedWorkspace] openURL:nsUrl];
	}
}

std::string tr(std::string_view english, const char* language)
{
	@autoreleasepool {
		NSBundle* bundle = [NSBundle mainBundle];
		if (language) {
			NSString* path = [bundle pathForResource:[NSString stringWithUTF8String:language]
			                                  ofType:@"lproj"];
			NSBundle* langBundle = path ? [NSBundle bundleWithPath:path] : nil;
			if (!langBundle) return std::string(english);
			bundle = langBundle;
		}
		NSString* key = [[NSString alloc] initWithBytes:english.data()
		                                         length:english.size()
		                                       encoding:NSUTF8StringEncoding];
		if (!key) return std::string(english);
		NSString* text = [bundle localizedStringForKey:key value:key table:nil];
		const char* utf8 = text ? text.UTF8String : nullptr;
		return utf8 ? std::string(utf8) : std::string(english);
	}
}

} // namespace openmsx::mac
