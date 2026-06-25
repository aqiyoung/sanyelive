cmake_minimum_required(VERSION 3.10)
project(crash_handler)

add_library(crash_handler SHARED crash_handler.c)
target_link_libraries(crash_handler log)
