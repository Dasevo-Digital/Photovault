# Downloadfehler und unvollständige Archive dürfen nie als fertiger Cache gelten.

# Beim include gemerkt: In einer Funktion zeigt CMAKE_CURRENT_LIST_DIR auf
# die aufrufende Datei.
set(PV_RUNTIME_DOWNLOAD_DIR "${CMAKE_CURRENT_LIST_DIR}")

# Holt ein Archiv der ONNX Runtime und entpackt es nach root.
#   default_base  Ordneradresse der Vorgabe (Freigabe von Microsoft)
#   archive_name  Dateiname, z. B. onnxruntime-linux-x64-1.28.3.tgz
#   override_sha  ONNXRUNTIME_ARCHIVE_SHA256 von Hand; leer = Prüfsummenliste
# Die Umgebungsvariable PV_ONNXRUNTIME_QUELLE ersetzt default_base durch eine
# eigene Ablage – eine Adresse oder file:// auf einen Ordner, an die der
# Archivname angehängt wird. Eine eigene Ablage braucht eine feste Summe.
function(pv_runtime_fetch default_base archive_name override_sha archive root)
  set(base "${default_base}")
  set(custom FALSE)
  if(NOT "$ENV{PV_ONNXRUNTIME_QUELLE}" STREQUAL "")
    set(base "$ENV{PV_ONNXRUNTIME_QUELLE}")
    set(custom TRUE)
  endif()
  string(REGEX REPLACE "/+$" "" base "${base}")
  set(url "${base}/${archive_name}")
  pv_runtime_pins("${archive_name}" "${override_sha}" shas)
  if("${shas}" STREQUAL "")
    if(custom)
      message(FATAL_ERROR "No pinned SHA256 for ${archive_name} (onnxruntime-pruefsummen.txt); "
                          "PV_ONNXRUNTIME_QUELLE is only accepted with a pinned archive")
    endif()
    message(WARNING "No pinned SHA256 for ${archive_name}; the archive is not verified")
  endif()
  message(STATUS "Downloading ONNX Runtime from: ${url}")
  pv_runtime_download("${url}" "${archive}" "${root}" "${shas}")
endfunction()

# Die erlaubten Summen eines Archivs: von Hand gesetzt oder aus der Liste.
function(pv_runtime_pins archive_name override_sha out_var)
  set(shas "")
  if(NOT "${override_sha}" STREQUAL "")
    string(TOLOWER "${override_sha}" shas)
  else()
    file(STRINGS "${PV_RUNTIME_DOWNLOAD_DIR}/../onnxruntime-pruefsummen.txt" lines)
    foreach(line IN LISTS lines)
      # Kein $ am Ende: Eine Windows-Arbeitskopie kann \r anhängen.
      if(line MATCHES "^([0-9a-f]+)  ([^ \r]+)")
        string(LENGTH "${CMAKE_MATCH_1}" length)
        if(length EQUAL 64 AND CMAKE_MATCH_2 STREQUAL archive_name)
          list(APPEND shas "${CMAKE_MATCH_1}")
        endif()
      endif()
    endforeach()
  endif()
  set(${out_var} "${shas}" PARENT_SCOPE)
endfunction()

# expected_sha: leer (ungeprüft) oder eine Liste erlaubter Summen.
function(pv_runtime_download url archive root expected_sha)
  get_filename_component(base "${root}" DIRECTORY)
  file(MAKE_DIRECTORY "${base}")
  set(stage "${base}/unpack")
  file(REMOVE_RECURSE "${stage}")
  file(MAKE_DIRECTORY "${stage}")
  set(ok FALSE)
  foreach(attempt RANGE 1 3)
    file(REMOVE "${archive}")
    file(DOWNLOAD "${url}" "${archive}" STATUS status TLS_VERIFY ON
         TIMEOUT 180 INACTIVITY_TIMEOUT 30)
    list(GET status 0 code)
    if(code EQUAL 0)
      set(ok TRUE)
      break()
    endif()
    file(REMOVE "${archive}")
    if(NOT attempt EQUAL 3)
      execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep 2)
    endif()
  endforeach()
  if(NOT ok)
    file(REMOVE_RECURSE "${stage}")
    message(FATAL_ERROR "ONNX Runtime download failed (${status}); no archive was cached")
  endif()
  if(NOT "${expected_sha}" STREQUAL "")
    file(SHA256 "${archive}" actual_sha)
    list(FIND expected_sha "${actual_sha}" found)
    if(found EQUAL -1)
      file(REMOVE "${archive}")
      file(REMOVE_RECURSE "${stage}")
      message(FATAL_ERROR "ONNX Runtime archive SHA256 differs from the pinned source (${actual_sha})")
    endif()
  endif()
  execute_process(COMMAND "${CMAKE_COMMAND}" -E tar xf "${archive}"
                  WORKING_DIRECTORY "${stage}" RESULT_VARIABLE extracted
                  ERROR_VARIABLE extraction_error)
  file(REMOVE "${archive}")
  get_filename_component(name "${root}" NAME)
  if(NOT extracted EQUAL 0 OR NOT EXISTS "${stage}/${name}/include/onnxruntime_cxx_api.h")
    file(REMOVE_RECURSE "${stage}")
    message(FATAL_ERROR "ONNX Runtime extraction failed (${extracted}): ${extraction_error}")
  endif()
  file(REMOVE_RECURSE "${root}")
  file(RENAME "${stage}/${name}" "${root}")
  file(REMOVE_RECURSE "${stage}")
endfunction()
