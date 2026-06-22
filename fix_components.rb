require 'fileutils'

def fix_file(filepath)
  content = File.read(filepath)
  original = content.dup

  content.gsub!(/DSToken\.Color\.primary/, 'DSToken.Color.textPrimary')
  content.gsub!(/DSToken\.Font/, 'DSToken.Typography')

  if content != original
    File.write(filepath, content)
    puts "Fixed API in #{filepath}"
  end
end

Dir.glob('Sources/Snippets/DesignSystem/Components/*.swift').each { |f| fix_file(f) }
