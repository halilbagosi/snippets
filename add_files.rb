require 'xcodeproj'

project_path = 'Snippets.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

files_to_add = [
  'Sources/Snippets/Views/Sidebar/CollectionEditorSheet.swift',
  'Sources/Snippets/Views/Sidebar/ModernSidebar.swift',
  'Sources/Snippets/Views/Components/SnippetCollectionCard.swift',
  'Sources/Snippets/Views/Components/GenieOverlay.swift'
]

files_to_add.each do |file_path|
  file_ref = project.main_group.find_file_by_path(file_path) || project.main_group.new_reference(file_path)
  
  # Check if it's already in the target's build phases
  unless target.source_build_phase.files_references.include?(file_ref)
    target.add_file_references([file_ref])
    puts "Added #{file_path}"
  else
    puts "Already in project: #{file_path}"
  end
end

project.save
puts "Project saved."
