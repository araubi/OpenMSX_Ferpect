#include "ImGuiOpenFile.hh"

#include "ImGuiManager.hh"

#include "FilePool.hh"
#include "Reactor.hh"
#include "ReadDir.hh"

#include "FileOperations.hh"
#include "MacFrontEnd.hh"
#include "one_of.hh"
#include "stl.hh"

#include <ImGuiFileDialog.h>
#include <imgui.h>

namespace openmsx {

void ImGuiOpenFile::save(ImGuiTextBuffer& buf)
{
	for (const auto& [key, value] : lastPath) {
		buf.appendf("%s=%s\n", key.c_str(), value.c_str());
	}
	auto bookmarks = ImGuiFileDialog::Instance()->SerializeBookmarks();
	buf.appendf("bookmarks=%s\n", bookmarks.c_str());
}

void ImGuiOpenFile::loadLine(std::string_view name, zstring_view value)
{
	if (name == "bookmarks") {
		ImGuiFileDialog::Instance()->DeserializeBookmarks(std::string(value));
	} else {
		lastPath[std::string(name)] = value;
	}
}

[[nodiscard]] static bool dirOnlyHasReadme(zstring_view directory)
{
	ReadDir dir(directory);
	while (const auto* d = dir.getEntry()) {
		auto name = std::string_view(d->d_name);
		if (name == one_of(std::string_view(".."), std::string_view("."))) continue;
		if (name != "README") return false;
	}
	return true;
}

[[nodiscard]] static std::string makeUniqueName(std::string_view proposedName, std::vector<std::string>& existingNames)
{
	std::string name{proposedName};
	int count = 1;
	while (contains(existingNames, name)) {
		name = strCat(proposedName, " (", ++count, ')');
	}
	existingNames.push_back(name);
	return name;
}

void ImGuiOpenFile::setBookmarks()
{
	auto& dialog = *ImGuiFileDialog::Instance();

	const auto& filePool = manager.getReactor().getFilePool();
	std::vector<std::string> existingNames;
	for (const auto& dir : filePool.getDirectories()) {
		using enum FileType;
		if ((dir.types & (ROM | DISK | TAPE)) == NONE) continue;

		auto path = std::string(FileOperations::getNativePath(std::string(dir.path)));
		if (!FileOperations::isDirectory(path)) continue;
		if (dirOnlyHasReadme(path)) continue;
		auto name = makeUniqueName(FileOperations::getFilename(dir.path), existingNames);
		dialog.RemoveBookmark(name);
		dialog.AddBookmark(name, path);
	}
}

std::string ImGuiOpenFile::getStartPath(zstring_view lastLocationHint)
{
	if (!lastLocationHint.empty()) {
		if (auto stat = FileOperations::getStat(lastLocationHint)) {
			if (FileOperations::isDirectory(*stat)) {
				return std::string(lastLocationHint);
			} else if (FileOperations::isRegularFile(*stat)) {
				return std::string(FileOperations::getDirName(lastLocationHint));
			}
		}
	}
	auto [it, inserted] = lastPath.try_emplace(lastTitle, ".");
	return it->second;
}

void ImGuiOpenFile::selectFile(const std::string& title, std::string filters,
                               const std::function<void(const std::string&)>& callback,
                               zstring_view lastLocationHint,
                               Painter painter_)
{
	if (!filters.contains("{.*}")) {
		filters += ",All files (*){.*}";
	}
	int extraFlags = ImGuiFileDialogFlags_DisableCreateDirectoryButton;
	common(title, filters.c_str(), callback, lastLocationHint, painter_, extraFlags);
}

void ImGuiOpenFile::selectNewFile(const std::string& title, std::string filters,
                                  const std::function<void(const std::string&)>& callback,
                                  zstring_view lastLocationHint,
                                  Painter painter_)
{
	if (!filters.contains("{.*}")) {
		filters += ",All files (*){.*}";
	}
	int extraFlags =
		ImGuiFileDialogFlags_DisableCreateDirectoryButton |
		ImGuiFileDialogFlags_ConfirmOverwrite;
	common(title, filters.c_str(), callback, lastLocationHint, painter_, extraFlags);
}

void ImGuiOpenFile::selectDirectory(const std::string& title,
                                    const std::function<void(const std::string&)>& callback,
                                    zstring_view lastLocationHint,
                                    Painter painter_)
{
	int extraFlags = 0;
	common(title, nullptr, callback, lastLocationHint, painter_, extraFlags);
}

void ImGuiOpenFile::common(const std::string& title, const char* filters,
                           const std::function<void(const std::string&)>& callback,
                           zstring_view lastLocationHint,
                           Painter painter_,
                           int extraFlags)
{
	if constexpr (mac::NATIVE_UI) {
		// FERPECT (macOS): the standard open/save panel instead of the
		// ImGui file dialog. Run it from the main loop, not from here
		// (we're in the middle of drawing a frame).
		bool directory = filters == nullptr;
		lastTitle = title;
		auto startPath = getStartPath(lastLocationHint);
		if (startPath == ".") startPath.clear();
		bool save = (extraFlags & ImGuiFileDialogFlags_ConfirmOverwrite) != 0;
		// "Name (*.a *.b){.a,.b},All files (*){.*}" -> a, b  (or none: any file)
		std::vector<std::string> extensions;
		bool any = false;
		if (filters) {
			std::string_view f = filters;
			while (true) {
				auto b = f.find('{');
				if (b == std::string_view::npos) break;
				auto e = f.find('}', b);
				if (e == std::string_view::npos) break;
				auto list = f.substr(b + 1, e - b - 1);
				while (!list.empty()) {
					auto c = list.find(',');
					auto ext = list.substr(0, c);
					list = (c == std::string_view::npos) ? std::string_view() : list.substr(c + 1);
					while (!ext.empty() && (ext.front() == ' ')) ext.remove_prefix(1);
					while (!ext.empty() && (ext.back()  == ' ')) ext.remove_suffix(1);
					if (ext == ".*") { any = true; continue; }
					// ".dsk.gz" -> "gz": the panel looks at the last part
					if (auto dot = ext.rfind('.'); dot != std::string_view::npos) {
						ext = ext.substr(dot + 1);
					}
					if (ext.empty() || ext.contains('*')) { any = true; continue; }
					if (!contains(extensions, ext)) extensions.emplace_back(ext);
				}
				f = f.substr(e + 1);
			}
		}
		// When saving the extensions say which one to add to the name.
		// When opening, "All files" means: don't grey out anything.
		if (any && !save) extensions.clear();
		manager.executeDelayed([this, title, callback, directory, save,
		                        extensions = std::move(extensions),
		                        startPath = std::move(startPath)] {
			auto result = save ? mac::runSavePanel(title, extensions, startPath)
			                   : mac::runOpenPanel(title, extensions, directory, startPath);
			if (!result) return;
			lastPath[title] = directory ? *result
			                            : std::string(FileOperations::getDirName(*result));
			if (callback) callback(*result);
		});
		return;
	}

	chooseDirectory = filters == nullptr;
	activePainter = painter_;
	setBookmarks();

	lastTitle = title;

	auto startPath = getStartPath(lastLocationHint);
	IGFD::FileDialogConfig config;
	config.path = startPath;
	config.flags = extraFlags |
		ImGuiFileDialogFlags_DontShowHiddenFiles |
		ImGuiFileDialogFlags_CaseInsensitiveExtention |
		ImGuiFileDialogFlags_Modal;
	ImGuiFileDialog::Instance()->OpenDialog(
		"FileDialog", title, filters, config);
	openFileCallback = callback;
}

void ImGuiOpenFile::doPaint()
{
	// (Modal) file dialog
	auto* fileDialog = ImGuiFileDialog::Instance();
	if (fileDialog->Display("FileDialog", ImGuiWindowFlags_NoCollapse, ImVec2(560.0f, 360.0f))) {
		if (fileDialog->IsOk() && openFileCallback) {
			lastPath[lastTitle] = fileDialog->GetCurrentPath();
			std::string filePathName = FileOperations::getConventionalPath( // Windows: replace backslash with slash
				chooseDirectory ? fileDialog->GetCurrentPath() : fileDialog->GetFilePathName());
			openFileCallback(filePathName);
			openFileCallback = {};
		}
		fileDialog->Close();
	}
}

std::string ImGuiOpenFile::getLastFilter()
{
	auto* fileDialog = ImGuiFileDialog::Instance();
	return fileDialog->GetCurrentFilter();
}

} // namespace openmsx
