require 'fileutils'

def fix_file(filepath)
  content = File.read(filepath)
  original = content.dup

  content.gsub!(/DSTag\(/, 'FilterTag(')

  if content != original
    File.write(filepath, content)
    puts "Fixed DSTag in #{filepath}"
  end
end

Dir.glob('Sources/Snippets/Views/**/*.swift').each { |f| fix_file(f) }
