# .github/scripts/sync-issues.rb
require 'octokit'
require 'date'
require 'fileutils'

# GitHub API 클라이언트 설정
client = Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])
til_repo = ENV['TIL_REPO']
blog_path = 'blog'

puts "Syncing TIL issues from #{til_repo} to blog..."

# 모든 TIL 이슈 가져오기 (페이지네이션 처리)
all_issues = []
page = 1
per_page = 100

loop do
  puts "Fetching page #{page}..."
  issues = client.issues(til_repo, state: 'all', per_page: per_page, page: page)
  break if issues.empty?
  
  til_issues = issues.select do |issue|
    issue.title.include?('[TIL]') || 
    issue.labels.any? { |label| label.name.downcase.include?('til') }
  end
  
  all_issues.concat(til_issues)
  page += 1
  
  # API 레이트 리밋 방지
  sleep(0.5)
end

puts "Found #{all_issues.length} TIL issues in total"

all_issues.each do |issue|
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
  
  # 제목 길이 제한
  display_title = clean_title
  if display_title.length > 50
    display_title = display_title.slice(0, 47) + "..."
  end
  
  # 파일명 생성
  filename = "#{post_date}-til.md"
  
  # TIL 카테고리로 고정하고 태그만 자동 분류
  categories = ['til']
  tags = ['TIL']
  
  title_lower = clean_title.downcase
  
  # 내용 기반으로 태그만 추가
  if title_lower.match(/java|jpa|spring|lombok|hibernate|gradle|maven/)
    tags << 'Java' if title_lower.match(/java|jpa|hibernate/)
    tags << 'Spring' if title_lower.include?('spring')
  end
  
  if title_lower.match(/javascript|js|node|express|axios|dom|bom|css|html|bootstrap|responsive|reactive/)
    tags << 'JavaScript'
    tags << 'CSS' if title_lower.include?('css')
    tags << 'HTML' if title_lower.include?('html')
  end
  
  if title_lower.match(/git|github|commit|rebase|fork|jenkins|actions|ci\/cd|devops/)
    tags << 'Git'
    tags << 'DevOps' if title_lower.match(/jenkins|actions|ci|devops/)
  end
  
  if title_lower.match(/algorithm|bfs|dfs|dp|그래프|트리/)
    tags << 'Algorithm'
  end
  
  if title_lower.match(/flask|python|django/)
    tags << 'Flask' if title_lower.include?('flask')
    tags << 'Python' if title_lower.include?('python')
  end
  
  if title_lower.match(/project|버티|msa|gateway|아키텍처|프로젝트/)
    tags << 'Project'
  end
  
  if title_lower.match(/aws|azure|gcp|cloud|iaas|paas|saas|docker|kubernetes/)
    tags << 'Cloud' if title_lower.match(/aws|azure|gcp|cloud|iaas|paas|saas/)
    tags << 'DevOps' if title_lower.match(/docker|kubernetes|jenkins|actions/)
  end
  
  tags.uniq!

  # Front Matter 생성 (title 필드 제거)
  front_matter = <<~FRONTMATTER
    ---
    layout: post
    collection: til
    description: >
      #{post_date} TIL
    categories: #{categories}
    tags: #{tags}
    date: #{post_date} 00:00:00
    last_modified_at: #{issue.updated_at.strftime('%Y-%m-%d %H:%M:%S')}
    github_issue: #{issue.number}
    github_url: #{issue.html_url}
    sitemap: false
    ---

  FRONTMATTER

  # 이슈 내용 처리
  content = issue.body || '내용이 없습니다.'
  
  # 기존의 TIL 헤딩 제거 (다양한 패턴 처리)
  content = content.gsub(/^#\s*\[?TIL\]?\s*-?\s*\d{4}-\d{2}-\d{2}.*?\n?/m, '')
  content = content.gsub(/^#\s*TIL\s*-?\s*\d{4}-\d{2}-\d{2}.*?\n?/m, '')
  
  # 메인 헤딩 추가 (# [TIL] 형태로)
  main_heading = "# [TIL] #{display_title}\n\n"
  
  # 메타데이터 추가
  metadata = <<~METADATA
    > 📝 **TIL (Today I Learned)**  
    > 🔗 **원본 이슈**: [##{issue.number}](#{issue.html_url})  
    > 📅 **작성일**: #{post_date}  
    > 🔄 **최종 수정**: #{issue.updated_at.strftime('%Y년 %m월 %d일')}

    ---

  METADATA

  # 최종 포스트 내용 (title 없이 구성)
  post_content = front_matter + main_heading + metadata + content

  # TIL 폴더에만 저장
  til_posts_dir = File.join(blog_path, 'til', '_posts')
  FileUtils.mkdir_p(til_posts_dir)
  
  # 기존 파일이 있는지 확인 (같은 날짜로)
  existing_files = Dir.glob(File.join(til_posts_dir, "#{post_date}-*.md"))
  
  if existing_files.any?
    # 기존 파일이 있으면 업데이트
    til_filepath = existing_files.first
    puts "  ✅ Updating existing TIL post: #{File.basename(til_filepath)}"
  else
    # 새 파일 생성
    til_filepath = File.join(til_posts_dir, filename)
    puts "  ✅ Creating new TIL post: #{filename}"
  end
  
  File.write(til_filepath, post_content)
  puts "  📁 Saved to: til/_posts/"
end

puts "🎉 Sync completed! Processed #{all_issues.length} TIL issues"
