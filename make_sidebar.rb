require 'fileutils'

content_view_main = File.read("ContentView_main.swift")
modern_sidebar = File.read("Sources/Snippets/Views/Sidebar/ModernSidebar.swift")

# We want to rewrite ModernSidebar to use the legacy ZStack layout.
# Let's extract the legacy sections from ContentView_main.swift
