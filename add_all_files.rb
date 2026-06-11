require 'xcodeproj'

project_path = 'Snippets.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

Dir.glob('Sources/**/*.swift').each do |file_path|
  file_ref = project.main_group.find_file_by_path(file_path) || project.main_group.new_reference(file_path)
  
  unless target.source_build_phase.files_references.include?(file_ref)
    target.add_file_references([file_ref])
    puts "Added #{file_path}"
  end
end

project.save
puts "Project saved."
