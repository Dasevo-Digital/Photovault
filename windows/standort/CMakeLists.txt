cmake_minimum_required(VERSION 3.14)
project(pv_standort LANGUAGES CXX)

# Konsolenprogramm, kein WIN32-Ziel: Es wird von der App aufgerufen und
# schreibt auf die Standardausgabe.
add_executable(pv_standort "pv_standort.cpp")

# C++20, damit C++/WinRT die Koroutinen aus <coroutine> nimmt. Unter C++17
# greift es auf <experimental/coroutine> zurueck, und das ist ab Visual
# Studio 2026 kein Hinweis mehr, sondern ein Fehler (STL1011).
target_compile_features(pv_standort PRIVATE cxx_std_20)
target_compile_definitions(pv_standort PRIVATE "NOMINMAX" "WIN32_LEAN_AND_MEAN"
                                               "UNICODE" "_UNICODE")
# windowsapp.lib ist die Importbibliothek fuer die WinRT-Laufzeit; die
# C++/WinRT-Kopfdateien kommen aus dem Windows SDK.
target_link_libraries(pv_standort PRIVATE "windowsapp.lib")
