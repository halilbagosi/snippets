require 'fileutils'

def migrate_file(filepath)
  content = File.read(filepath)
  original = content.dup

  content.gsub!(/\.padding\(28\)/, '.padding(DSToken.Spacing.xl)')
  content.gsub!(/\.padding\(14\)/, '.padding(DSToken.Spacing.md)')
  content.gsub!(/\.padding\(7\)/, '.padding(DSToken.Spacing.xs)')
  content.gsub!(/\.padding\(6\)/, '.padding(DSToken.Spacing.xs)')
  content.gsub!(/\.padding\(2\)/, '.padding(DSToken.Spacing.xxs)')

  if content != original
    File.write(filepath, content)
    puts "Fixed padding in #{filepath}"
  end
end

Dir.glob('Sources/Snippets/Views/**/*.swift').each { |f| migrate_file(f) }
