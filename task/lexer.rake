rule '.rb' => '.rl' do |task|
  sh "ragel -R -F1 #{task.source} -o #{task.name}"
end

rule '.c' => ['.rl', 'ext/ragel/base_lexer.rl'] do |task|
  sh "ragel -C -I ext/ragel -G2 #{task.source} -o #{task.name}"
end

rule '.java' => ['.rl', 'ext/ragel/base_lexer.rl'] do |task|
  sh "ragel -J -I ext/ragel #{task.source} -o #{task.name}"
end

file 'ext/ragel/base_lexer_rubified.rl' => ['ext/ragel/base_lexer.rl',
                                            'ext/ragel/base_lexer_rubifier.rb'] do |task|
  sh "ruby ext/ragel/base_lexer_rubifier.rb < #{task.source} > #{task.name}"
end

file 'ext/pureruby/oga/native/lexer.rb' => ['ext/pureruby/oga/native/lexer.rl',
                                            'ext/ragel/base_lexer_rubified.rl'] do |task|
  sh "ragel -R -I ext/ragel -F1 #{task.source} -o #{task.name}"
end

desc 'Generates the lexers'
multitask :lexer => [
  'ext/c/lexer.c',
  'ext/java/org/liboga/xml/Lexer.java',
  'ext/pureruby/oga/native/lexer.rb',
  'lib/oga/xpath/lexer.rb',
  'lib/oga/css/lexer.rb'
]
