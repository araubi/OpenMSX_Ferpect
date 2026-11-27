#!/usr/bin/env python3
"""FERPECT: writes the texts of the native macOS interface.

  python3 build/package-darwin/localize.py

Writes build/package-darwin/es.lproj/Localizable.strings (and an empty
en.lproj one: the English texts are the keys) from the table below, and
lists the texts of src/imgui/ImGuiManager.cc (buildNativeMenu) that have no
translation yet. The files are property lists in XML, which macOS accepts
for .strings files and which can't be written wrong by hand.
"""
import os
import plistlib
import re

ES = {
    # application menu
    "openMSX": "openMSX",
    "About openMSX": "Acerca de openMSX",
    "Services": "Servicios",
    "Hide openMSX": "Ocultar openMSX",
    "Hide Others": "Ocultar otros",
    "Show All": "Mostrar todo",
    "Quit openMSX": "Salir de openMSX",
    # File
    "File": "Archivo",
    "Open...": "Abrir…",
    "Open a cartridge, disk, cassette or other file": "Abrir un cartucho, disco, cinta u otro archivo",
    "Cartridge Slot": "Ranura de cartucho",
    "Disk Drive": "Unidad de disco",
    "Cassette": "Cinta",
    "Insert...": "Insertar…",
    "Insert a cartridge": "Insertar un cartucho",
    "Insert a disk": "Insertar un disco",
    "Insert a cassette": "Insertar una cinta",
    "Eject": "Expulsar",
    "Rewind": "Rebobinar",
    "More Options...": "Más opciones…",
    "Tape Deck...": "Reproductor de cintas…",
    "Quick Load State": "Cargar estado rápido",
    "Quick Save State": "Guardar estado rápido",
    "Load State...": "Cargar estado…",
    "Load a saved state": "Cargar un estado guardado",
    "Save Screenshot": "Guardar captura de pantalla",
    "Screenshot Options...": "Opciones de captura de pantalla…",
    "Record Audio/Video...": "Grabar audio y vídeo…",
    "Close": "Cerrar",
    # Edit
    "Edit": "Edición",
    "Copy Screen Text": "Copiar el texto de la pantalla",
    "Paste into the MSX": "Pegar en el MSX",
    # Machine
    "Machine": "Máquina",
    "Pause": "Pausa",
    "Reset": "Reiniciar",
    "Power": "Encendido",
    "Full Speed": "Velocidad máxima",
    "Fast Forward": "Avance rápido",
    "Full Speed When Loading": "Velocidad máxima al cargar",
    "Select MSX Machine...": "Elegir máquina MSX…",
    "Test MSX Hardware...": "Probar el hardware MSX…",
    "Reverse Bar": "Barra de rebobinado",
    # View
    "View": "Visualización",
    "Full Screen": "Pantalla completa",
    "Normal Size (x1)": "Tamaño normal (x1)",
    "Double Size (x2)": "Tamaño doble (x2)",
    "Triple Size (x3)": "Tamaño triple (x3)",
    "Quadruple Size (x4)": "Tamaño cuádruple (x4)",
    "PAL TV Proportions": "Proporción de televisor PAL",
    "Full Stretch": "Estirar a toda la pantalla",
    "Deinterlace": "Desentrelazar",
    "Deflicker": "Quitar parpadeo",
    "VSync": "Sincronía vertical",
    "Status Bar": "Barra de estado",
    "Tool Windows as Mac Windows": "Ventanas de herramientas como ventanas de Mac",
    "openMSX Menu Bar in the Window": "Barra de menús de openMSX en la ventana",
    # Settings
    "Settings": "Ajustes",
    "Mute": "Silenciar",
    "Sound Chip Settings...": "Ajustes de los chips de sonido…",
    "Grab Input": "Capturar el ratón y el teclado",
    "Configure MSX Joysticks...": "Configurar los joysticks MSX…",
    "Edit Shortcuts...": "Editar los atajos…",
    "Select Font...": "Elegir tipo de letra…",
    "Configure OSD Icons...": "Configurar los iconos en pantalla…",
    "Configure Messages...": "Configurar los mensajes…",
    "Menu Language": "Idioma de los menús",
    "System Default": "Por defecto (el del sistema)",
    "English": "Inglés",
    "Spanish": "Castellano",
    # Tools
    "Tools": "Herramientas",
    "Console": "Consola",
    "Virtual Keyboard": "Teclado virtual",
    "Message Log": "Registro de mensajes",
    "Disk Manipulator": "Manipulador de discos",
    "Trainer Selector": "Selector de trucos",
    "Cheat Finder": "Buscador de trucos",
    "SCC Viewer": "Visor de SCC",
    "MSX-Music Viewer": "Visor de MSX-Music",
    "Audio Channel Viewer": "Visor de canales de audio",
    "Plotter Viewer": "Visor del plotter",
    "Slot Map": "Mapa de slots",
    "I/O Ports": "Puertos de E/S",
    # Debugger
    "Debugger": "Depurador",
    "Tool Bar": "Barra de herramientas",
    "Disassembly": "Desensamblado",
    "CPU Registers": "Registros de la CPU",
    "CPU Flags": "Indicadores de la CPU",
    "Slots": "Slots",
    "Stack": "Pila",
    "Memory": "Memoria",
    "Breakpoints": "Puntos de ruptura",
    "Symbol Manager": "Gestor de símbolos",
    "Watch Expression": "Expresiones vigiladas",
    "Probe/Trace Viewer": "Visor de sondas y trazas",
    "VDP Bitmap Viewer": "Visor de mapa de bits del VDP",
    "VDP Tile Viewer": "Visor de patrones del VDP",
    "VDP Sprite Viewer": "Visor de sprites del VDP",
    "Raster Beam Viewer": "Visor del haz de barrido",
    "VDP Register Viewer": "Visor de registros del VDP",
    "Palette Editor": "Editor de paleta",
    # Window
    "Window": "Ventana",
    "Minimize": "Minimizar",
    "Zoom": "Zoom",
    "Bring All to Front": "Traer todo al frente",
    # Help
    "Help": "Ayuda",
    "FAQ": "Preguntas frecuentes",
    "Setup Guide": "Guía de instalación",
    "User Manual": "Manual de uso",
    "About openMSX (credits)": "Acerca de openMSX (créditos)",
}

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))

src = open(os.path.join(root, 'src', 'imgui', 'ImGuiManager.cc'), encoding='utf-8').read()
src = src[src.index('ImGuiManager::buildNativeMenu()'):]
found = set(re.findall(
    r'\b(?:item|command|toggle|setting|submenu|open|manual|T|tr|nativeTr)\(\s*"((?:[^"\\]|\\.)*)"', src))
found |= set(re.findall(r'\bstandard\(\s*S::\w+,\s*"((?:[^"\\]|\\.)*)"', src))
found |= set(re.findall(r'"([^"]*Size \(x\d\))"', src))
found |= {"System Default", "English", "Spanish"}

for lang, table in (('es', ES), ('en', {})):
    d = os.path.join(here, lang + '.lproj')
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, 'Localizable.strings'), 'wb') as f:
        plistlib.dump(dict(sorted(table.items())), f, fmt=plistlib.FMT_XML)

missing = sorted(found - set(ES))
for k in missing:
    print('without translation:', k)
unused = sorted(set(ES) - found)
for k in unused:
    print('not in the source:', k)
print(len(found), 'texts,', len(missing), 'without translation')
