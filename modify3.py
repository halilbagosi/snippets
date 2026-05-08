import re

with open('/Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift', 'r') as f:
    content = f.read()

# 1. State
context_enum = '''    enum SidebarSelectionContext: Equatable {
        case recent
        case library
    }
    @State private var sidebarSelectionContext: SidebarSelectionContext? = nil'''
content = content.replace(
    '@State private var selectedSnippetID: PersistentIdentifier? = nil',
    '@State private var selectedSnippetID: PersistentIdentifier? = nil\n' + context_enum
)

# 2. gallerySnippets onSelect
content = content.replace(
    '''                        onSelect: { snippet in
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                selectedSnippetID = snippet.persistentModelID
                            }
                        },''',
    '''                        onSelect: { snippet in
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                selectedSnippetID = snippet.persistentModelID
                                sidebarSelectionContext = .library
                            }
                        },'''
)

# 3. isPresentingNew sheet onSave
content = content.replace(
    '''                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    selectedSnippetID = newSnippet.persistentModelID
                }''',
    '''                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    selectedSnippetID = newSnippet.persistentModelID
                    sidebarSelectionContext = .library
                }'''
)

# 4. recentRow
content = content.replace(
    '''        let isActive = selectedSnippetID == snippet.persistentModelID
        Button {
            selectedSnippetID = snippet.persistentModelID
        } label: {
            HStack(spacing: 8) {
                Circle()''',
    '''        let isActive = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .recent
        Button {
            selectedSnippetID = snippet.persistentModelID
            sidebarSelectionContext = .recent
        } label: {
            HStack(spacing: 8) {
                Circle()''',
    1 # Only replace the first occurrence (recentRow is first)
)

# 5. sidebarSnippetRow
content = content.replace(
    '''        let isActive = selectedSnippetID == snippet.persistentModelID
        Button {
            selectedSnippetID = snippet.persistentModelID
        } label: {
            HStack(spacing: 8) {
                Circle()''',
    '''        let isActive = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .library
        Button {
            selectedSnippetID = snippet.persistentModelID
            sidebarSelectionContext = .library
        } label: {
            HStack(spacing: 8) {
                Circle()'''
)

# 6. ModernSidebar Signature
content = content.replace(
    '''    @Binding var selectedSnippetID: PersistentIdentifier?
    @Binding var selectedCollectionID: PersistentIdentifier?''',
    '''    @Binding var selectedSnippetID: PersistentIdentifier?
    @Binding var sidebarSelectionContext: ContentView.SidebarSelectionContext?
    @Binding var selectedCollectionID: PersistentIdentifier?'''
)
content = content.replace(
    '''            selectedSnippetID: $selectedSnippetID,
            selectedCollectionID: $selectedCollectionID,''',
    '''            selectedSnippetID: $selectedSnippetID,
            sidebarSelectionContext: $sidebarSelectionContext,
            selectedCollectionID: $selectedCollectionID,'''
)

# 7. ModernSidebar Selection enum
content = content.replace(
    '''        case collection(PersistentIdentifier)
        case snippet(PersistentIdentifier)
    }''',
    '''        case collection(PersistentIdentifier)
        case snippet(PersistentIdentifier)
        case recentSnippet(PersistentIdentifier)
    }'''
)

# 8. ModernSidebar selection binding
old_binding = '''        Binding(
            get: {
                if let id = selectedSnippetID { return .snippet(id) }
                if let id = selectedCollectionID { return .collection(id) }
                if let lang = selectedLanguage { return .language(lang.rawValue) }
                return .all
            },
            set: { newValue in
                switch newValue {
                case .all, .none:
                    selectedLanguage = nil
                    selectedSnippetID = nil
                    selectedCollectionID = nil
                case .language(let raw):
                    selectedLanguage = SupportedLanguage(rawValue: raw)
                    selectedSnippetID = nil
                    selectedCollectionID = nil
                case .collection(let id):
                    selectedCollectionID = id
                    selectedLanguage = nil
                    selectedSnippetID = nil
                case .snippet(let id):
                    selectedSnippetID = id
                }
            }
        )'''

new_binding = '''        Binding(
            get: {
                if let id = selectedSnippetID {
                    return sidebarSelectionContext == .recent ? .recentSnippet(id) : .snippet(id)
                }
                if let id = selectedCollectionID { return .collection(id) }
                if let lang = selectedLanguage { return .language(lang.rawValue) }
                return .all
            },
            set: { newValue in
                switch newValue {
                case .all, .none:
                    selectedLanguage = nil
                    selectedSnippetID = nil
                    selectedCollectionID = nil
                case .language(let raw):
                    selectedLanguage = SupportedLanguage(rawValue: raw)
                    selectedSnippetID = nil
                    selectedCollectionID = nil
                case .collection(let id):
                    selectedCollectionID = id
                    selectedLanguage = nil
                    selectedSnippetID = nil
                case .snippet(let id):
                    selectedSnippetID = id
                    sidebarSelectionContext = .library
                case .recentSnippet(let id):
                    selectedSnippetID = id
                    sidebarSelectionContext = .recent
                }
            }
        )'''

content = content.replace(old_binding, new_binding)

# 9. Recent section tag
# Find the exact string in the Recent section:
recent_section_code = '''            if !recentSnippets.isEmpty {
                Section("Recent", isExpanded: $isRecentSectionExpanded) {
                    ForEach(recentSnippets) { snippet in
                        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
                        let accent = Color(hex: language.accentHex) ?? .accentColor
                        Label {
                            Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } icon: {
                            Circle()
                                .fill(accent)
                                .frame(width: 8, height: 8)
                        }
                        .tag(Selection.snippet(snippet.persistentModelID))'''

recent_section_code_new = recent_section_code.replace('.tag(Selection.snippet(snippet.persistentModelID))', '.tag(Selection.recentSnippet(snippet.persistentModelID))')

content = content.replace(recent_section_code, recent_section_code_new)

with open('/Users/halilbagosi/snippets/Sources/Snippets/Views/ContentView.swift', 'w') as f:
    f.write(content)
