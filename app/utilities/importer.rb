class Importer

  Log = Motion::Log

  def self.load(url, &block)
    Log.debug "Loading deck from #{url}"
    AFMotion::HTTP.get(url) do |result|

      if result.nil? or result.body.nil?
        block.call(nil, nil, nil) if block
        next
      end

      Log.verbose 'Loading : OK'
      doc = Wakizashi::HTML(result.body)

      case url
        when /hearthpwn\.com\/decks/i
          deck, clazz, title = self.hearthpwn_deck(doc)
        when /hearthpwn\.com\/deckbuilder/i
          deck, clazz, title = self.hearthpwn_deckbuilder(url, doc)
        #when /hearthstone\.judgehype\.com/i
        #  deck, clazz, title = self.judgehype(doc)
        when /hearthstone-decks\.com/i
          deck, clazz, title = self.hearthstone_decks(doc)
        when /hearthstats\.net/i
          deck, clazz, title = self.hearthstats(doc)
        when /hearthhead\.com\/deck=/
          deck, clazz, title = self.hearthhead_deck(url, doc)
        when /hearthnews\.fr/
          deck, clazz, title = self.hearthnews(doc)
        else
          Log.warn "unknown url #{url}"
          block.call(nil, nil, nil) if block
          next
      end

      if deck.nil? or deck.count.zero?
        block.call(nil, nil, nil) if block
        next
      end

      deck = Sorter.sort_cards(deck)
      block.call(deck, clazz, title) if block
    end
  end

  def self.netdeck(&block)
    pasteboard = NSPasteboard.generalPasteboard
    paste      = pasteboard.stringForType NSPasteboardTypeString

    if paste and /^(trackerimport|netdeckimport)/ =~ paste
      lines = paste.split("\n")

      deck      = []
      deck_name = ''
      lines.drop(1).each do |line|
        if /^name:/ =~ line
          deck_name = line.split(':').last
          Log.verbose "found deck name '#{deck_name}'"
          next
        end

        if /^url:/ =~ line or /^arena:/ =~ line
          # futur work
          next
        end

        card = Card.by_english_name line
        next if card.nil?
        Log.verbose "found card #{line}"
        if deck.include? card
          deck.each do |c|
            if c.card_id == card.card_id
              card.count += 1
            end
          end
        else
          card.count = 1
          deck << card
        end
      end

      clazz = nil
      deck.each do |card|
        unless card.player_class.nil?
          clazz = card.player_class
          next
        end
      end

      Log.verbose "found deck #{deck_name} for class #{clazz}"
      deck = Sorter.sort_cards(deck)
      block.call(deck, clazz, deck_name) if block
    end

    Dispatch::Queue.main.after(1) do
      netdeck(&block)
    end
  end

  private
  # import deck from http://www.hearthstone-decks.com
  # accepted urls :
  # http://www.hearthstone-decks.com/deck/voir/yu-gi-oh-rogue-5215
  def self.hearthstone_decks(doc)
    deck = []

    title       = nil
    clazz       = nil

    # search for title
    title_nodes = doc.xpath("//div[@id='content']//h3")
    unless title_nodes.nil? or title_nodes.size.zero?
      title_node = title_nodes.first
      title      = title_node.children.last.stringValue.strip
    end

    # search for clazz
    clazz_nodes = doc.xpath("//input[@id='classe_nom']")
    unless clazz_nodes.nil? or clazz_nodes.size.zero?
      clazz_node = clazz_nodes.first

      clazz = clazz_node['value']
      if clazz
        classes = {
            'Chaman'    => 'shaman',
            'Chasseur'  => 'hunter',
            'Démoniste' => 'warlock',
            'Druide'    => 'druid',
            'Guerrier'  => 'warrior',
            'Mage'      => 'mage',
            'Paladin'   => 'paladin',
            'Prêtre'    => 'priest',
            'Voleur'    => 'rogue'
        }
        clazz   = classes[clazz]
      end
    end

    # search for cards
    cards_nodes = doc.xpath("//table[contains(@class,'tabcartes')]//tbody//tr")
    cards_nodes.each do |card_node|
      children = card_node.children

      count     = children[0].stringValue.to_i
      card_name = children[1].stringValue.strip

      card = Card.by_french_name(card_name)
      if card.nil?
        Log.warn "CARD : #{card_name} is nil"
        next
      end
      card.count = count
      deck << card
    end

    return deck, clazz, title
  end

  # import deck from http://hearthstone.judgehype.com
  # accepted urls :
  # http://hearthstone.judgehype.com/deck/12411/
  def self.judgehype(doc)
    deck = []

    title       = nil
    clazz       = nil

    # search for title
    title_nodes = doc.xpath("//div[@id='contenu-titre']//h1")
    unless title_nodes.nil? or title_nodes.size.zero?
      title_node = title_nodes.first
      title      = title_node.children.last.stringValue.strip
    end

    # search for clazz
    clazz_nodes = doc.xpath("//div[@id='contenu']//img")
    unless clazz_nodes.nil? or clazz_nodes.size.zero?
      clazz_node = clazz_nodes.first

      match = /select-(\w+)\.png/.match clazz_node.XMLString
      unless match.nil?
        classes = {
            'chaman'    => 'shaman',
            'chasseur'  => 'hunter',
            'demoniste' => 'warlock',
            'druide'    => 'druid',
            'guerrier'  => 'warrior',
            'mage'      => 'mage',
            'paladin'   => 'paladin',
            'pretre'    => 'priest',
            'voleur'    => 'rogue'
        }
        clazz   = classes[match[1]]
      end
    end

    # search for cards
    cards_nodes = doc.xpath("//table[contains(@class,'contenu')][1]//tr")
    cards_nodes.each do |card_node|
      children = card_node.children

      next unless children.size >= 3
      td_node = children[3]
      next if td_node.nil?

      td_children = td_node.children
      next unless td_children.size == 3
      count     = /\d+/.match td_children[0].stringValue
      card_name = td_children[2].stringValue

      Log.verbose "#{card_name} x #{count[0].to_i}"
      card = Card.by_french_name(card_name)
      if card.nil?
        Log.warn "CARD : #{card_name} is nil"
        next
      end
      card.count = count[0].to_i
      deck << card
    end

    return deck, clazz, title
  end

  # fetch and parse a deck from http://www.hearthpwn.com/decks/
  def self.hearthpwn_deck(doc)
    title       = nil
    clazz       = nil

    # search for class
    clazz_nodes = doc.xpath("//span[contains(@class,'class')]")
    unless clazz_nodes.nil? or clazz_nodes.size.zero?
      clazz_node = clazz_nodes.first
      match      = /class-(\w+)/.match clazz_node.XMLString
      unless match.nil?
        clazz = match[1]
      end
    end

    # search for title
    title_nodes = doc.xpath("//h2[contains(@class,'t-deck-title')]")
    unless title_nodes.nil? or title_nodes.size.zero?
      title_node = title_nodes.first
      title      = title_node.stringValue
    end

    # search for cards
    card_nodes = doc.xpath("//td[contains(@class,'col-name')]")
    if card_nodes.nil? or card_nodes.size.zero?
      return nil, nil, nil
    end

    deck = []
    card_nodes.each do |node|
      card_name = node.elementsForName 'b'

      next if card_name.nil?

      card_name = card_name.first.stringValue

      count = /\d+/.match node.children.lastObject.stringValue

      card = Card.by_english_name(card_name)
      if card.nil?
        Log.warn "CARD : #{card_name} is nil"
        next
      end
      Log.verbose "card #{card_name} is #{card}"
      card.count = count[0].to_i
      deck << card
    end

    return deck, clazz, title
  end

  # fetch and parse a deck from http://www.hearthpwn.com/deckbuilder
  def self.hearthpwn_deckbuilder(url, doc)
    deck  = []

    # search for class
    clazz = url.partition('#').first.split('/').last

    # search for cards
    cards = url.partition('#').last.split(';').map { |x| x.split ':' }
    cards.each do |card_id_arr|
      card_id = card_id_arr[0]
      count   = card_id_arr[1]

      path = "//tr[@data-id='#{card_id}']/td[1]/b"

      node = doc.xpath(path)
      next if node.nil? or node.size.zero?
      card_name = node.first.stringValue

      card = Card.by_english_name(card_name)
      if card.nil?
        Log.warn "CARD : #{card_name} is nil"
        next
      end
      card.count = count.to_i
      deck << card
    end

    return deck, clazz, nil
  end

  # fetch and parse a deck from http://www.hearthstats.net/decks/
  def self.hearthstats(doc)
    title       = nil
    clazz       = nil

    # search for class
    clazz_nodes = doc.xpath("//div[contains(@class,'win-count')]//img")
    unless clazz_nodes.nil? or clazz_nodes.size.zero?
      clazz_nodes.each do |clazz_node|
        match = /\/assets\/Icons\/Classes\/(\w+)_Icon\.gif/.match clazz_node['src']
        if match
          clazz = match[1].downcase
          next
        end
      end
    end

    # search for title
    title_nodes = doc.xpath("//h1[contains(@class,'page-title')]")
    unless title_nodes.nil? or title_nodes.size.zero?
      title_node = title_nodes.first
      small      = title_node.elementsForName 'small'
      if small
        title_node.removeChild small.first
      end
      title = title_node.stringValue
    end

    # search for cards
    card_nodes = doc.xpath("//div[contains(@class,'cardWrapper')]")
    if card_nodes.nil? or card_nodes.size.zero?
      return nil, nil, nil
    end

    deck = []
    card_nodes.each do |node|
      next if node.children.count < 5

      card_name = node.children[1].stringValue
      count     = node.children[2].stringValue.to_i

      next if card_name.nil? || count.nil?

      card = Card.by_english_name(card_name)
      if card.nil?
        Log.warn "CARD : #{card_name} is nil"
        next
      end
      Log.verbose "card #{card_name} is #{card}"
      card.count = count
      deck << card
    end

    return deck, clazz, title
  end

  # fetch and parse a deck from http://www.hearthhead.net/deck=
  def self.hearthhead_deck(url, doc)
    title = nil
    clazz = nil

    locale      = case url
                    when /de\.hearthhead\.com/
                      'deDE'
                    when /es\.hearthhead\.com/
                      'esES'
                    when /fr\.hearthhead\.com/
                      'frFR'
                    when /pt\.hearthhead\.com/
                      'ptPT'
                    when /ru\.hearthhead\.com/
                      'ruRU'
                    else
                      'enUS'
                  end

    # search for class
    clazz_nodes = doc.xpath("//div[@class='deckguide-hero']")
    unless clazz_nodes.nil? or clazz_nodes.size.zero?
      clazz_node = clazz_nodes.first
      classes    = {
          1  => 'Warrior',
          2  => 'Paladin',
          3  => 'Hunter',
          4  => 'Rogue',
          5  => 'Priest',
          # 6 => 'Death-Knight'
          7  => 'Shaman',
          8  => 'Mage',
          9  => 'Warlock',
          11 => 'Druid'
      }
      clazz      = classes[clazz_node['data-class'].to_i]
    end

    # search for title
    title_nodes = doc.xpath("//h1[@id='deckguide-name']")
    unless title_nodes.nil? or title_nodes.size.zero?
      title_node = title_nodes.first
      title      = title_node.stringValue
    end

    # search for cards
    card_nodes = doc.xpath("//div[contains(@class,'deckguide-cards-type')]/ul/li")
    if card_nodes.nil? or card_nodes.size.zero?
      return nil, nil, nil
    end

    deck = []
    card_nodes.each do |node|
      card_node = node.children.first
      card_name = card_node.stringValue
      node.removeChild card_node

      count = /\d+/.match node.stringValue
      if count.nil?
        count = 1
      else
        count = count[0].to_i
      end

      next if card_name.nil? || count.nil?

      card = Card.by_name_and_locale(card_name, locale)
      if card.nil?
        Log.warn "CARD : #{card_name} is nil"
        next
      end
      Log.verbose "card #{card_name} is #{card}"
      card.count = count
      deck << card
    end

    return deck, clazz, title
  end

  # fetch and parse a deck from http://www.hearthnews.fr
  def self.hearthnews(doc)
    title       = nil
    clazz       = nil

    # search for class
    clazz_nodes = doc.xpath('//div[@hero_class]')
    unless clazz_nodes.nil? or clazz_nodes.size.zero?
      clazz_node = clazz_nodes.first
      clazz      = clazz_node['hero_class'].downcase
    end

    # search for title
    title_nodes = doc.xpath("//div[@class='block_deck_content_deck_name']")
    unless title_nodes.nil? or title_nodes.size.zero?
      title_node = title_nodes.first
      title      = title_node.stringValue.strip
    end

    # search for cards
    card_nodes = doc.xpath("//a[@class='real_id']")
    if card_nodes.nil? or card_nodes.size.zero?
      return nil, nil, nil
    end

    deck = []
    card_nodes.each do |node|
      card_id = node['real_id']
      count = node['nb_card'].to_i

      next if card_id.nil? || count.nil?

      card = Card.by_id(card_id)
      if card.nil?
        Log.warn "CARD : #{card_id} is nil"
        next
      end
      Log.verbose "card #{card_id} is #{card}"
      card.count = count
      deck << card
    end

    return deck, clazz, title
  end

end