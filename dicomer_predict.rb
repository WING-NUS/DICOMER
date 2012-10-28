#!/usr/bin/ruby

require 'rubygems'
require "/home/linzihen/prog/pdtb-parser-v120415/src/parser"
require 'getopt/std'

SVM_LIGHT_CLASSIFIER = "/home/linzihen/tools/svm_light/svm_classify"

@nouns = %w/NN NNS NNP NNPS/ 
@verbs = %w/VB VBD VBG VBN VBP VBZ/
@adjs = %w/JJ JJR JJS/ 
@advs = %w/RB RBR RBS/ 
@tags = nil

def prepare_svm_file(grid_str, to_fh, use_type=1, use_arg=true, dummy_tag=true, remove_all_nil=true, combine_nil=false, threshold=2, use_adj=true, subseq_len=3, svm_file_format=1, rouge_feat=false, use_ps_ss=false, in_cell=true, use_synset=false, peer_only=false, use_nonexp_exp=true)
    if use_adj then
        @tags = @nouns + @verbs + @adjs + @advs
    else
        @tags = @nouns + @verbs
    end

    types = []
    if use_type == 2 then
        disc_types = %w/Asynchronous Synchrony Cause Pragmatic-cause Condition Pragmatic-condition Contrast Pragmatic-contrast 
            Concession Pragmatic-concession Conjunction Instantiation Restatement Alternative Exception List 
            EntRel NoRel/ 
    elsif use_type == 1 then
        disc_types = %w/Temporal Contingency Comparison Expansion EntRel NoRel/
    elsif use_type == 0 then
        disc_types = %w/E/
    else
        puts 'error: use type'
        exit
    end

    disc_types.each do |rel|
        types << rel
    end

    if use_arg then
        types2 = []
        types.each do |rel|
            %w/1 2/.each do |a|
                types2 << rel+'.'+a
            end
        end
        types = types2
    end

    if use_ps_ss and use_nonexp_exp then
        types2 = []
        types.each do |rel|
            types2 << 'PS.'+rel
            types2 << 'SS.'+rel
            types2 << 'NonExp.'+rel
            types2 << 'Exp.'+rel
            %w/PS SS/.each do |aa|
                %w/NonExp Exp/.each do |bb|
                    types2 << aa+'.'+bb+'.'+rel
                end
            end
        end
        types = types + types2
    elsif use_nonexp_exp then
        types2 = []
        types.each do |rel|
            types2 << 'NonExp.'+rel
            types2 << 'Exp.'+rel
        end
        types = types + types2
    elsif use_ps_ss then
        types2 = []
        types.each do |rel|
            types2 << 'PS.'+rel
            types2 << 'SS.'+rel
        end
        types = types + types2
    end

    types << 'nil'
    
    ngram2id = Hash.new
    i = 1

    unigrams = Array.new
    if dummy_tag then
        start_tag = ['start']
        end_tag = ['end']
    else
        start_tag = []
        end_tag = []
    end
    (types+start_tag+end_tag).each { |t1| unigrams << t1 }
    unigrams.each { |a| ngram2id[a] = i; i += 1 }

    if subseq_len >= 2 then
    bigrams = Array.new
    (start_tag+types).each { |t1| (types+end_tag).each { |t2| bigrams << t1+'>'+t2 }}
    bigrams.each { |a| ngram2id[a] = i; i += 1 }
    end
    
    if subseq_len >= 3 then
    trigrams = Array.new
    (start_tag+types).each { |t1| types.each { |t2| (types+end_tag).each { |t3| trigrams << t1+'>'+t2+'>'+t3 }}}
    trigrams.each { |a| ngram2id[a] = i; i += 1 }
    end

    if subseq_len >= 4 then
    fourgrams = Array.new
    (start_tag+types).each { |t1| types.each { |t2| types.each { |t3| (types+end_tag).each { |t4| fourgrams << t1+'>'+t2+'>'+t3+'>'+t4 }}}}
    fourgrams.each { |a| ngram2id[a] = i; i += 1 }
    end

    if subseq_len >= 5 then
    fivegrams = Array.new
    (start_tag+types).each { |t1| types.each { |t2| types.each { |t3| types.each { |t4| (types+end_tag).each { |t5| fivegrams << t1+'>'+t2+'>'+t3+'>'+t4+'>'+t5 }}}}}
    fivegrams.each { |a| ngram2id[a] = i; i += 1 }
    end
    
    if in_cell then
        bigrams = Array.new
        types.each { |t1| types.each { |t2| bigrams << t1+'_'+t2 }}
        bigrams.each { |a| ngram2id[a] = i; i += 1 }
    end

    if threshold > 1 then
        curr_max = ngram2id.size
        ngram2id.keys.each do |k| 
            ngram2id[k+'_low'] = ngram2id[k] + curr_max
        end
    end

    last_fid = ngram2id.size + 1

    table = generate_matrix(grid_str, use_type, use_arg, dummy_tag, remove_all_nil, combine_nil, threshold, use_adj, subseq_len, use_ps_ss, in_cell, use_synset, use_nonexp_exp)
    perm = table.map {|k,v| [ngram2id[k], v]} .sort {|a,b| a[0] <=> b[0]} .map {|id,v| id.to_s+':'+v.to_s} .join(' ')
    to_fh.puts '0 ' + perm 
end


def convert_type(type)
    case type
    when 'Asynchronous', 'Synchrony' then 'Temporal'
    when 'Cause', 'Pragmatic-cause', 'Condition', 'Pragmatic-condition' then 'Contingency'
    when 'Contrast', 'Pragmatic-contrast', 'Concession', 'Pragmatic-concession' then 'Comparison'
    when 'Conjunction', 'Instantiation', 'Restatement', 'Alternative', 'Exception', 'List' then 'Expansion'
    when 'EntRel', 'NoRel' then type
    when 'Temporal', 'Contingency', 'Comparison', 'Expansion' then type
    else puts "error: no such type - #{type}"; exit
    end
end


def convert_pos(pos)
    if @nouns.include?(pos) then
        'n'
    elsif @verbs.include?(pos) then
        'v'
    elsif @adjs.include?(pos) then
        'a'
    elsif @advs.include?(pos) then
        'r'
    else
        's'
    end
end


def generate_matrix(grid_str, use_type, use_arg, dummy_tag, remove_all_nil, combine_nil, threshold, use_adj, subseq_len, use_ps_ss, in_cell, use_synset, use_nonexp_exp)
    events = Array.new([])
    grid = Hash.new {|h,k| h[k] = Hash.new {|h1,k1| h1[k1] = Array.new}}
    max = -1
    eval(grid_str).each do |id, term_hsh|
        sid = id + 1
        term_hsh.each do |p_t, type_hsh|
            pos, t = p_t.split('_')
            next if not @tags.include?(pos) 
            pos2 = convert_pos(pos)
            t = t.downcase.stem
            events << t
            type_hsh.keys.map do |a| 
                arr = a.split('.')
                if use_type == 2 then
                    disc_type = arr[3]
                elsif use_type == 1 then
                    disc_type = convert_type(arr[3])
                elsif use_type == 0 then
                    disc_type = 'E'
                end
                if use_arg then
                    type = disc_type+'.'+arr[4]
                else
                    type = disc_type
                end

                grid[sid][t] << type if not grid[sid][t].include?(type)
                if use_nonexp_exp and use_ps_ss then
                    grid[sid][t] << arr[0]+'.'+type if not grid[sid][t].include?(arr[0]+'.'+type)
                    grid[sid][t] << arr[1]+'.'+type if not grid[sid][t].include?(arr[1]+'.'+type)
                    grid[sid][t] << arr[0]+'.'+arr[1]+'.'+type if not grid[sid][t].include?(arr[0]+'.'+arr[1]+'.'+type)
                elsif use_ps_ss then
                    grid[sid][t] << arr[0]+'.'+type if not grid[sid][t].include?(arr[0]+'.'+type)
                elsif use_nonexp_exp then
                    grid[sid][t] << arr[1]+'.'+type if not grid[sid][t].include?(arr[1]+'.'+type)
                end

            end 
        end
        max = sid if sid > max
    end

    events.uniq!

    low_freq_e = Array.new
    events.each do |e|
        cnt = 0
        grid.each_key do |i|
            if not grid[i][e].empty? then
                cnt += 1
            end
        end
        if cnt < threshold then
            low_freq_e << e
        end
    end
    if dummy_tag then
        events.each do |e|
            grid[0][e] = ['start']
            grid[max+1][e] = ['end']
        end
        start_i = 0
        last_i = max + 1
    else
        start_i = 1
        last_i = max
    end
    high_freq_e = events - low_freq_e

    table = generate_table(high_freq_e, grid, start_i, last_i, '', remove_all_nil, combine_nil, subseq_len)
    if threshold > 1 then
        table2 = generate_table(low_freq_e, grid, start_i, last_i, '_low', remove_all_nil, combine_nil, subseq_len) 
        table = table.to_a + table2.to_a
    end

    if in_cell then
        table3 = generate_table_in_cell(low_freq_e, grid, start_i, last_i, '', remove_all_nil, combine_nil, subseq_len) 
        table = table.to_a + table3.to_a
        if threshold > 1 then
            table4 = generate_table_in_cell(low_freq_e, grid, start_i, last_i, '_low', remove_all_nil, combine_nil, subseq_len) 
            table = table.to_a + table4.to_a
        end
    end
    
    table
end


def generate_table(events, grid, start_i, last_i, suffix, remove_all_nil, combine_nil, subseq_len)
    table1 = Hash.new(0); cnt1 = 0
    if subseq_len >= 2 then
    table2 = Hash.new(0); cnt2 = 0
    end
    if subseq_len >= 3 then
    table3 = Hash.new(0); cnt3 = 0
    end
    if subseq_len >= 4 then
    table4 = Hash.new(0); cnt4 = 0
    end
    if subseq_len >= 5 then
    table5 = Hash.new(0); cnt5 = 0
    end

    inc = 1

    events.sort.each do |e|

        seq = Array.new
        (start_i..last_i).each do |i|
            seq << grid[i][e].sort #if grid[i][e] != []
        end

        (0...seq.size).each do |i|
            rel1s = seq[i] == [] ? ['nil'] : seq[i]
            rel1s.each do |rel1|
                next if remove_all_nil and rel1 == 'nil'
                table1[rel1 + suffix] += inc
                cnt1 += inc
            end
        end

        if subseq_len >= 2 then
        (0...seq.size-1).each do |i|
            rel1s = seq[i] == [] ? ['nil'] : seq[i]
            rel2s = seq[i+1] == [] ? ['nil'] : seq[i+1]
            rel1s.each do |rel1|
                rel2s.each do |rel2|
                    ss = rel1 + '>' + rel2
                    next if remove_all_nil and ss == 'nil>nil'
                    table2[ss + suffix] += inc
                    cnt2 += inc
                end
            end
        end
        (0...seq.size).each do |i|
            rels = seq[i].sort
            next if rels.size <= 1
            (0...rels.size-1).each do |i1|
                next if not rels[i1].match(/^PS/)
                (1...rels.size).each do |i2|
                    next if not rels[i2].match(/^SS/)
                    ss = rels[i1] + '>' + rels[i2]
                    table2[ss + suffix] += inc
                    cnt2 += inc
                end
            end
        end
        end

        if subseq_len >= 3 then
        (0...seq.size-2).each do |i|
            rel1s = seq[i] == [] ? ['nil'] : seq[i]
            rel2s = seq[i+1] == [] ? ['nil'] : seq[i+1]
            rel3s = seq[i+2] == [] ? ['nil'] : seq[i+2]
            rel1s.each do |rel1|
                rel2s.each do |rel2|
                    rel3s.each do |rel3|
                        ss = rel1 + '>' + rel2 + '>' + rel3
                        next if remove_all_nil and ss == 'nil>nil>nil'
                        if combine_nil and ss.match('nil>nil') then
                            table2[ss.sub(/nil>nil/, 'nil') + suffix] += inc
                            cnt2 += inc
                        else
                            table3[ss + suffix] += inc
                            cnt3 += inc
                        end
                    end
                end
            end
        end
        end

        if subseq_len >= 4 then
        (0...seq.size-3).each do |i|
            rel1s = seq[i] == [] ? ['nil'] : seq[i]
            rel2s = seq[i+1] == [] ? ['nil'] : seq[i+1]
            rel3s = seq[i+2] == [] ? ['nil'] : seq[i+2]
            rel4s = seq[i+3] == [] ? ['nil'] : seq[i+3]
            rel1s.each do |rel1|
                rel2s.each do |rel2|
                    rel3s.each do |rel3|
                        rel4s.each do |rel4|
                            ss = rel1 + '>' + rel2 + '>' + rel3 + '>' + rel4
                            next if remove_all_nil and ss == 'nil>nil>nil>nil'
                            if combine_nil and ss.match('nil>nil>nil') then
                                table2[ss.sub(/nil>nil>nil/, 'nil') + suffix] += inc
                                cnt2 += inc
                            elsif combine_nil and ss.match('nil>nil') then
                                table3[ss.sub(/nil>nil/, 'nil') + suffix] += inc
                                cnt3 += inc
                            else
                                table4[ss + suffix] += inc
                                cnt4 += inc
                            end
                        end
                    end
                end
            end
        end
        end

        if subseq_len >= 5 then
        (0...seq.size-4).each do |i|
            rel1s = seq[i] == [] ? ['nil'] : seq[i]
            rel2s = seq[i+1] == [] ? ['nil'] : seq[i+1]
            rel3s = seq[i+2] == [] ? ['nil'] : seq[i+2]
            rel4s = seq[i+3] == [] ? ['nil'] : seq[i+3]
            rel5s = seq[i+4] == [] ? ['nil'] : seq[i+4]
            rel1s.each do |rel1|
                rel2s.each do |rel2|
                    rel3s.each do |rel3|
                        rel4s.each do |rel4|
                            rel5s.each do |rel5|
                                ss = rel1 + '>' + rel2 + '>' + rel3 + '>' + rel4 + '>' + rel5
                                next if remove_all_nil and ss == 'nil>nil>nil>nil>nil'
                                if combine_nil then
                                    ss = ss.gsub(/nil(>nil)+/,'nil')
                                end
                                case ss.split('>').size
                                when 2 then table2[ss + suffix] += inc; cnt2 += inc
                                when 3 then table3[ss + suffix] += inc; cnt3 += inc
                                when 4 then table4[ss + suffix] += inc; cnt4 += inc
                                when 5 then table5[ss + suffix] += inc; cnt5 += inc
                                end
                            end
                        end
                    end
                end
            end
        end
        end
    end

    table1.each {|k,v| table1[k] = v.to_f / cnt1}
    table = table1.to_a
    if subseq_len >= 2 then
        table2.each {|k,v| table2[k] = v.to_f / cnt2}
        table += table2.to_a
    end
    if subseq_len >= 3 then
        table3.each {|k,v| table3[k] = v.to_f / cnt3}
        table += table3.to_a
    end
    if subseq_len >= 4 then
        table4.each {|k,v| table4[k] = v.to_f / cnt4}
        table += table4.to_a
    end
    if subseq_len >= 5 then
        table5.each {|k,v| table5[k] = v.to_f / cnt5}
        table += table5.to_a
    end

    #table1.merge(table2).merge(table3)
    #table1.to_a + table2.to_a + table3.to_a + table4.to_a + table5.to_a
    table
end


def generate_table_in_cell(events, grid, start_i, last_i, suffix, remove_all_nil, combine_nil, subseq_len)
    table0 = Hash.new(0); cnt0 = 0

    inc = 1

    events.sort.each do |e|
        seq = Array.new
        (start_i..last_i).each do |i|
            seq << grid[i][e].sort #if grid[i][e] != []
        end

        (0...seq.size).each do |i|
            rels = seq[i].sort
            next if rels.size <= 1
            (0...rels.size-1).each do |i1|
                #next if not rels[i1].match(/^PS/)
                (1...rels.size).each do |i2|
                    #next if not rels[i2].match(/^SS/)
                    ss = rels[i1] + '_' + rels[i2]
                    table0[ss + suffix] += 1
                    cnt0 += 1
                end
            end
        end
    end

    table0.each {|k,v| table0[k] = v.to_f / cnt0}
    table0.to_a
end


if __FILE__ == $0 then
    sent_split = false
    begin
        opt = Getopt::Std.getopts("sd:f:o:")
        sent_split = opt["s"] ? true : false
        in_dir = opt["d"] 
        in_f = opt["f"]
        out_f = opt["o"]
        if out_f == nil or (in_dir == nil and in_f == nil) or (in_dir != nil and in_f != nil and out_f != nil) then
            raise
        end
    rescue
        puts "usage: #{__FILE__} [-d input-directory | -f input-file] -o output-file\n"+
        "-s : use sentence split, default no\n"+
        "-d input-directory : input directory of summary files\n"+
        "-f input-file : input summary file\n"+
        "-o output-file : output result file"
        exit
    end

    parser = Parser.new

    tmp_f = "/tmp/pdtb_" + rand.to_s + rand.to_s
    svm_f = "/tmp/pdtb_" + rand.to_s + rand.to_s + '.svm'
    svm_fh = File.open(svm_f, 'w')
    files = []

    if in_f != nil then
        files << in_f
        File.open(tmp_f, 'w') do |tmp_fh|
            tmp_fh.puts File.readlines(in_f).join.gsub(/[\r\n][\r\n]+/, "\n").strip
        end

        article = parser.parse_text(tmp_f, sent_split)
        grid_str = article.get_sent_term_types
        prepare_svm_file(grid_str, svm_fh)
    else
        Dir.glob(in_dir+'/*').sort.each do |f|
            puts File.basename(f)
            files << File.basename(f)
            File.open(tmp_f, 'w') do |tmp_fh|
                tmp_fh.puts File.readlines(f).join.gsub(/[\r\n][\r\n]+/, "\n").strip
            end

            article = parser.parse_text(tmp_f, sent_split)
            grid_str = article.get_sent_term_types
            prepare_svm_file(grid_str, svm_fh)
        end
    end

    svm_fh.close
    
    `#{SVM_LIGHT_CLASSIFIER} #{svm_f} #{File.dirname(__FILE__)}/tac09-10-type1-arg-sal-incell-imp.model #{tmp_f}`
    ans = File.readlines(tmp_f)
    File.open(out_f, 'w') do |out_fh|
        files.each do |a|
            out_fh.puts a+' '+ans.shift
        end
    end

    FileUtils.rm_f(tmp_f)
    FileUtils.rm_f(svm_f)
end
