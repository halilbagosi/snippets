require 'xcodeproj'

project_path = 'Snippets.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Add the WebPreview folder as a resources folder reference
target = project.targets.first
group = project.main_group.find_subpath(File.join('Sources', 'Snippets', 'Resources'), true)
web_preview_dir = File.join('Sources', 'Snippets', 'Resources', 'WebPreview')

# Create a folder reference (last argument 'true' makes it a folder reference)
file_ref = group.new_reference(web_preview_dir)
file_ref.last_known_file_type = 'folder'

# Add to the resources build phase
target.resources_build_phase.add_file_reference(file_ref)

project.save
puts "Added WebPreview folder reference to project."
