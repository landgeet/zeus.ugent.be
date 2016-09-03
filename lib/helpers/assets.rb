module AssetHelper
  def asset(type, identifier)
    {
      img: "<img src='/assets/images/#{identifier}'/>",
      js: "<script src='/assets/scripts/#{identifier}.js'></script>",
      css: "<link rel='stylesheet' type='text/css' href='/assets/stylesheets/#{identifier}.css'>"
    }[type]
  end

  def zeus_logo_url(color: :black)
    "/assets/images/zeuslogo#{'_white' if color == :white}.svg"
  end
end