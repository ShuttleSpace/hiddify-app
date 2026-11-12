# N-API module carrying the VPN tun fd across the OHOS process boundary.
# See vpn_fd_relay.cpp for why the relay is needed at all.
cmake_minimum_required(VERSION 3.5.0)
project(hiddifyvpn)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH})

add_library(hiddifyvpn SHARED vpn_fd_relay.cpp)

target_link_libraries(hiddifyvpn PUBLIC libace_napi.z.so)
