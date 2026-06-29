require 'fileutils'

# 1. Update SnippetsApp.swift to remove configureWindows completely
app_path = "Sources/Snippets/SnippetsApp.swift"
app_content = File.read(app_path)

new_app_content = app_content.gsub(/        configureWindows\(NSApp\.windows\)\n/, "")
new_app_content = new_app_content.gsub(/        configureWindows\(sender\.windows\)\n/, "")

# Remove the configureWindows function
func_start = new_app_content.index("    private func configureWindows")
func_end = new_app_content.index("}\n#endif", func_start) if func_start

if func_start && func_end
  new_app_content = new_app_content[0...func_start] + new_app_content[func_end..-1]
end

File.write(app_path, new_app_content)
puts "Updated SnippetsApp.swift"

# 2. Update ModernSidebar.swift to remove opaque background
sidebar_path = "Sources/Snippets/Views/Sidebar/ModernSidebar.swift"
sidebar_content = File.read(sidebar_path)

new_sidebar_content = sidebar_content.gsub(/            theme\.canvasDeep\.ignoresSafeArea\(\)\n/, "")

# Add .toolbar { ToolbarItem(placement: .navigation) { ... } }? 
# Wait, native traffic light buttons and native sidebar button are automatic if we use NavigationSplitView and DO NOT hide the titlebar.
# We just need to make sure the sidebar uses the native material. 
# NavigationSplitView applies it natively, but if the content is a ZStack/ScrollView, it might not look right unless we explicitly add .background(.regularMaterial) or if we just let it be transparent.
# Let's test with just transparent.

File.write(sidebar_path, new_sidebar_content)
puts "Updated ModernSidebar.swift"
