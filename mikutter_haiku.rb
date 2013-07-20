# -*- coding:utf-8 -*-
################################################################################
##  mikutter_haiku
##    https://github.com/Akkiesoft/mikutter_haiku
##

## mikutter_haikuはご覧のスポンサーでお送りします
require 'net/http'
require 'uri'
require 'json'
require 'time'


## START
Plugin.create(:mikutter_haiku) do

  ########################################
  ## Writer :: 投稿処理
  ##
  def postToHaiku(message)
    # 設定が入ってるかチェック
    cant_post = 0
    hatena_id = UserConfig[:hatena_id]
    if hatena_id=='' then
      cant_post = 1
    end
    hatena_api_pass = UserConfig[:hatena_api_pass]
    if hatena_api_pass=='' then
      cant_post = 1
    end
    
    if cant_post == 1 then
      timeline(:mikutter_haiku) << Message.new({
        :message => "投稿に必要な設定がありません。設定画面でIDとパスワードを設定してください('ω`)",
        :system => true
      })
    else
      begin
        res = Net::HTTP.post_form(
          URI.parse("http://#{hatena_id}:#{hatena_api_pass}@h.hatena.ne.jp/api/statuses/update.json"),
          {'keyword'=>"id:#{hatena_id}", 'status'=>message, 'source'=>'mikutter_haiku'}
        )
      rescue => ee
        timeline(:mikutter_haiku) << Message.new({
          :message => "投稿に失敗しました。\n#{ee}",
          :system => true
        })
      end
	end
  end

  ########################################
  ## Reader :: リロード処理
  ##
  def reload
    (UserConfig[:haiku_url]|| []).select{|m|!m.empty?}.each do |url|
      # パースに失敗した場合は例外引っ掛けてスルー
      begin
        uri = URI.parse("#{url}?body_formats=haiku")
        json = Net::HTTP.get(uri)
        items = JSON.parse(json)
      rescue => ee
        timeline(:mikutter_haiku) << Message.new({
          :message => "JSONのパースに失敗しました\n#{url}?body_formats=haiku\n#{ee}",
          :system => true
        })
      else
        # TODO:クリアしないで追記読み込みできるようにする
        timeline(:mikutter_haiku).clear

        i = 0
        allcnt = 1
        items.each do |item|
          keyword	= item['target']['title']
          body		= item['haiku_text']
          link		= item['link']
          source	= item['source']
          time		= Time.parse(item['created_at'])

          # URL記法対応
          sintaxes = body.split('[')
          if sintaxes[0] != body then
            sintaxes.each do |sintax|
              pos = sintax.index(']')
              if pos.nil? then
                next		# これは記法ではない
              end
              sintax = sintax.slice(0, pos);
              sintaxOut = sintax.gsub(/(https?:\/\/[-_.!~*\'()a-zA-Z0-9;\/?:\@&=+\$,%#]+)\:title=(.+)/, "\\2( \\1 )");
              body = body.gsub("[#{sintax}]", "#{sintaxOut}");
            end
          end

          # はてなフォトライフ
          sintaxes = body.scan(/f:id:([-_a-zA-Z0-9]+):([0-9]{8})([0-9]{6})(j|g|p|f)?(:image|:movie)?/i) {|match|
            foto_id		= match[0];
            foto_initial	= foto_id.slice(0, 1);
            foto_date		= match[1];
            foto_time		= match[2];
            foto_type		= (defined?(match[3])) ? match[3] : '';
            foto_mode		= (defined?(match[4])) ? match[4] : '';
            foto_ext		= 'jpg';
            foto_ext		= 'gif' if foto_type == 'g'
            foto_ext		= 'png' if foto_type == 'p'
            foto_org		= "f:id:#{foto_id}:#{foto_date}#{foto_time}"
            foto_org		+= foto_type if foto_type
            foto_org		+= foto_mode if foto_mode
            foto_img		= "http://cdn-ak.f.st-hatena.com/images/fotolife/#{foto_initial}/#{foto_id}/#{foto_date}/#{foto_date}#{foto_time}.#{foto_ext}"
            foto_link		= "http://f.hatena.ne.jp/#{foto_id}/#{foto_date}#{foto_time}"
            if foto_type == "f" && foto_mode == ":movie" then
              body = body.sub("#{foto_org}", "#{foto_link}")
            else
              body = body.sub("#{foto_org}", "#{foto_img}")
            end
          }

          user		= User.new({
            :id					=> allcnt,
            :idname				=> item['user']['screen_name'],
            :name				=> item['user']['name'],
            :profile_image_url	=> item['user']['profile_image_url'],
            :url				=> item['user']['url']
          })
          timeline(:mikutter_haiku) << Message.new({
            :id => allcnt,
            :message => "#{link}\n\n<#{keyword}>\n#{body}",
            :user => user,
            :source => source,
            :created => time
          })
          i += 1
          allcnt += 1
        end
      end
    end
  end

  ########################################
  ## Reader :: タブの作成
  ##
  btn = Gtk::Button.new('更新')
  tab(:mikutter_haiku, 'はてなハイク') do
    set_icon File.expand_path(File.join(File.dirname(__FILE__), 'logo.png'))
    shrink
    nativewidget Gtk::HBox.new(false, 0).closeup(btn)
    expand
    timeline :mikutter_haiku
  end

  ########################################
  ## Reader :: 更新ボタンがクリックされた時
  ##
  btn.signal_connect('clicked'){ |elm|
    reload
  }

  ########################################
  ## Reader :: 1分に1度 自動で更新
  ##
  on_period do
    if(UserConfig[:haiku_auto])
      reload
    end
  end

  ########################################
  ## Reader :: 起動時に読み込み
  ##
  if(UserConfig[:haiku_exec])
    reload
  end

  ########################################
  ## Writer :: ハイクに投稿する
  ##
  command(:post_to_haiku,
  		name: 'ハイクに投稿する',
  		condition: lambda{ |opt| true },
  		visible: true,
  		role: :postbox) do |opt|
	begin
		message = Plugin.create(:gtk).widgetof(opt.widget).widget_post.buffer.text
		postToHaiku(message)
		defactivity "Haiku_post", "Haiku_Post"
		activity :Haiku_Post, "ハイクに投稿しました"
		Plugin.create(:gtk).widgetof(opt.widget).widget_post.buffer.text = ''
	end
  end

  ########################################
  ##  Writer :: ハイクとTwitterに投稿する
  ##
  command(:post_to_haiku_and_twitter,
  		name: 'ハイクとTwitterに投稿する',
  		condition: lambda{ |opt| true },
  		visible: true,
  		role: :postbox) do |opt|
	begin
		message = Plugin.create(:gtk).widgetof(opt.widget).widget_post.buffer.text
		Service.primary.update(:message => message)
		postToHaiku(message)
		defactivity "Haiku_post", "Haiku_Post"
		activity :Haiku_Post, "ハイクとTwitterに投稿しました"
		Plugin.create(:gtk).widgetof(opt.widget).widget_post.buffer.text = ''
	end
  end

  ########################################
  ##  Settings :: 設定画面
  ##
  settings "はてなハイク" do
    settings "投稿の設定(BASIC認証タイプじゃ)" do
      input("はてなID",:hatena_id)
      input("APIパスワード",:hatena_api_pass)
    end
    settings "タイムライン" do
      boolean('起動時に更新する', :haiku_exec)
      boolean('1分毎に自動更新を行う', :haiku_auto)
      multi "ハイクJSON URL", :haiku_url
    end
  end

end