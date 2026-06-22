require 'fileutils'

def migrate_file(filepath)
  content = File.read(filepath)
  original = content.dup

  # Corner Radii
  content.gsub!(/\.cornerRadius\((22\.0|22)\)/, '.cornerRadius(DSToken.Radius.lg)')
  content.gsub!(/\.cornerRadius\((16\.0|16)\)/, '.cornerRadius(DSToken.Radius.md)')
  content.gsub!(/\.cornerRadius\((8\.0|8)\)/, '.cornerRadius(DSToken.Radius.sm)')
  content.gsub!(/\.cornerRadius\((5\.0|5)\)/, '.cornerRadius(DSToken.Radius.xs)')
  content.gsub!(/\.cornerRadius\(999\)/, '.cornerRadius(DSToken.Radius.capsule)')

  # Padding
  content.gsub!(/\.padding\((32\.0|32)\)/, '.padding(DSToken.Spacing.xl)')
  content.gsub!(/\.padding\((24\.0|24)\)/, '.padding(DSToken.Spacing.lg)')
  content.gsub!(/\.padding\((16\.0|16)\)/, '.padding(DSToken.Spacing.md)')
  content.gsub!(/\.padding\((12\.0|12)\)/, '.padding(DSToken.Spacing.sm)')
  content.gsub!(/\.padding\((8\.0|8)\)/, '.padding(DSToken.Spacing.xs)')
  content.gsub!(/\.padding\((4\.0|4)\)/, '.padding(DSToken.Spacing.xxs)')

  # LiquidGlass
  content.gsub!(/LiquidGlassToggleStyle\(\)/, 'DSToggle()')
  content.gsub!(/LanguageBadge\(/, 'DSBadge(')
  content.gsub!(/FilterTag\(/, 'DSTag(')

  if content != original
    File.write(filepath, content)
    puts "Migrated #{filepath}"
  end
end

Dir.glob('Sources/Snippets/Views/**/*.swift').each do |file|
  migrate_file(file)
end
Dir.glob('Sources/Snippets/Features/**/*.swift').each do |file|
  migrate_file(file)
end
