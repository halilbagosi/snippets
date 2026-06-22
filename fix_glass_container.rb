require 'fileutils'

def fix_file(filepath)
  content = File.read(filepath)
  original = content.dup

  content.gsub!(/LiquidGlassContainer/, 'DSGlassContainer')

  if content != original
    File.write(filepath, content)
    puts "Fixed DSGlassContainer in #{filepath}"
  end
end

Dir.glob('Sources/Snippets/Views/**/*.swift').each { |f| fix_file(f) }
Dir.glob('Sources/Snippets/Features/**/*.swift').each { |f| fix_file(f) }
