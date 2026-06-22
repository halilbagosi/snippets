require 'fileutils'

def fix_file(filepath)
  content = File.read(filepath)
  original = content.dup

  content.gsub!(/DSBadge\(/, 'LanguageBadge(')

  if content != original
    File.write(filepath, content)
    puts "Fixed DSBadge in #{filepath}"
  end
end

Dir.glob('Sources/Snippets/Views/**/*.swift').each { |f| fix_file(f) }
