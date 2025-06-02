# .github/scripts/sync-issues.rb
require 'octokit'
require 'date'
require 'fileutils'

# GitHub API 클라이언트 설정
client = Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])
til_repo = ENV['TIL_REPO']
blog_path = 'blog'

puts "Syncing TIL issues from #{til_repo} to blog..."

# TIL 라벨이 있는 최근 이슈들 가져오기 (최근 10개)
issues = client.issues(til_repo, state: 'all', per_page: 10)
til_issues = issues.select do |issue|
  issue.title.include?('[TIL]') || 
  issue.labels.any? { |label| label.name.downcase.include?('til') }
end

puts "Found #{til_issues.length} TIL issues"

til_issues.each do |issue|
  puts "Processing issue ##{issue.number}: #{issue.title}"
  
  # 날짜 추출 (제목에서 YYYY-MM-DD 형식 찾기)
  date_match = issue.title.match(/(\d{4}-\d{2}-\d{2})/)
  if date_match
    post_date = date_match[1]
  else
    # 날짜가 없으면 이슈 생성일 사용
    post_date = issue.created_at.strftime('%Y-%m-%d')
  end
  
  # 제목에서 [TIL] 부분과 날짜 제거하여 클린한 제목 생성
  clean_title = issue.title
    .gsub(/\[TIL\]\s*/, '')
    .gsub(/#{Regexp.escape(post_date)}\s*/, '')
    .strip
  
  # 파일명 생성
  title_slug = clean_title.downcase
    .gsub(/[^a-z0-9\s가-힣-]/, '')  # 한글 포함한 특수문자 제거
    .gsub(/\s+/, '-')               # 공백을 하이픈으로
    .gsub(/-+/, '-')                # 연속 하이픈 제거
    .strip
    .slice(0, 50)                   # 길이 제한

  filename = "#{post_date}-#{title_slug}.md"
  
  # 카테고리 자동 분류 (제목 키워드 기반)
  categories = []
  tags = ['TIL']
  
  title_lower = clean_title.downcase
  
  case title_lower
  when /java|jpa|spring|lombok|hibernate|gradle|maven/
    categories << 'java' if title_lower.match(/java|jpa|hibernate|gradle|maven/)
    categories << 'spring' if title_lower.include?('spring')
    tags << 'Java' if title_lower.match(/java|jpa|hibernate/)
    tags << 'Spring' if title_lower.include?('spring')
  when /javascript|js|node|express|axios|dom|bom|css|html|bootstrap|responsive|reactive/
    categories << 'javascript'
    tags << 'JavaScript'
    tags << 'CSS' if title_lower.include?('css')
    tags << 'HTML' if title_lower.include?('html')
  when /git|github|commit|rebase|fork|jenkins|actions|ci\/cd|devops/
    categories << 'git'
    tags << 'Git'
    tags << 'DevOps' if title_lower.match(/jenkins|actions|ci|devops/)
  when /algorithm|bfs|dfs|dp|그래프|트리/
    categories << 'algorithm'
    tags << 'Algorithm'
  when /flask|python|django/
    categories << 'flask'
    tags << 'Flask' if title_lower.include?('flask')
    tags << 'Python' if title_lower.include?('python')
  when /project|버티|msa|gateway|아키텍처|프로젝트/
    categories << 'projectdiary'
    tags << 'Project'
  when /aws|azure|gcp|cloud|iaas|paas|saas|docker|kubernetes/
    categories << 'miscellaneous'
    tags << 'Cloud' if title_lower.match(/aws|azure|gcp|cloud|iaas|paas|saas/)
    tags << 'DevOps' if title_lower.match(/docker|kubernetes|jenkins|actions/)
  else
    categories << 'miscellaneous'
  end
  
  categories = ['til'] if categories.empty?
  primary_category = categories.first

  # Front Matter 생성
  front_matter = <<~FRONTMATTER
    ---
    layout: post
    title: "#{clean_title.gsub('"', '\"')}"
    description: >
      #{clean_title}에 대한 TIL 기록
    categories: #{categories}
    tags: #{tags}
    date: #{post_date} 00:00:00
    last_modified_at: #{issue.updated_at.strftime('%Y-%m-%d %H:%M:%S')}
    github_issue: #{issue.number}
    github_url: #{issue.html_url}
    sitemap: false
    ---

  FRONTMATTER

  # 이슈 내용 처리 - 첫 번째 헤딩 중복 제거
  content = issue.body || '내용이 없습니다.'
  
  # "# TIL - YYYY-MM-DD" 형태의 헤딩이 있다면 제거 (블로그에서 제목으로 표시되므로)
  content = content.gsub(/^#\s*TIL\s*-\s*\d{4}-\d{2}-\d{2}\s*\n?/, '')
  
  # 메타데이터 추가
  metadata = <<~METADATA
    > 📝 **TIL (Today I Learned)**  
    > 🔗 **원본 이슈**: [##{issue.number}](#{issue.html_url})  
    > 📅 **작성일**: #{post_date}  
    > 🔄 **최종 수정**: #{issue.updated_at.strftime('%Y년 %m월 %d일')}

    ---

  METADATA

  # 최종 포스트 내용
  post_content = front_matter + metadata + content

  # 블로그 _posts 폴더에 저장
  posts_dir = File.join(blog_path, '_posts')
  FileUtils.mkdir_p(posts_dir)
  
  posts_filepath = File.join(posts_dir, filename)
  
  # 기존 파일이 있는지 확인 (같은 이슈 번호로)
  existing_files = Dir.glob(File.join(posts_dir, "*issue-#{issue.number}*.md"))
  
  if existing_files.any?
    posts_filepath = existing_files.first
    puts "  ✅ Updating existing post: #{File.basename(posts_filepath)}"
  else
    # 새 파일명에 이슈 번호 포함하여 중복 방지
    filename_with_issue = "#{post_date}-#{title_slug}-issue-#{issue.number}.md"
    posts_filepath = File.join(posts_dir, filename_with_issue)
    puts "  ✅ Creating new post: #{filename_with_issue}"
  end
  
  File.write(posts_filepath, post_content)
  
  # 카테고리별 폴더에도 저장 (블로그 구조에 맞게)
  category_dir = File.join(blog_path, primary_category, '_posts')
  if Dir.exist?(File.join(blog_path, primary_category))
    FileUtils.mkdir_p(category_dir)
    category_filename = File.basename(posts_filepath)
    category_filepath = File.join(category_dir, category_filename)
    File.write(category_filepath, post_content)
    puts "  📁 Also saved to category: #{primary_category}/_posts/"
  end
end

puts "🎉 Sync completed! Processed #{til_issues.length} TIL issues"