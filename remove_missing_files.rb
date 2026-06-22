require 'xcodeproj'

project_path = 'Snippets.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Iterate through all file references and remove ones that don't exist
project.files.each do |file|
  path = file.real_path.to_s
  unless File.exist?(path)
    puts "Removing missing file reference: #{path}"
    file.remove_from_project
  end
end

project.save
puts "Project saved."
