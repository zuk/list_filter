# Painless list filtering for Rails.
#
# You have a view that shows a large list of records. You want to give your users
# the ability to filter the results using checkboxes, pulldown selects, text search,
# etc. You might also want the user's filter settings to stay in the session,
# so that when they go back to the list of records, their settings are retained.
#
# ListFilter does all of this for you. It gathers up the params from the filter form,
# stores them in the session (when appropriate), and builds the SQL conditions
# to constrain the list tof records based on the user's filter.
#
#
# === Example
#
# Okay so lets say you have a large list of books. You want your users to be
# able to filter by author (by id), title (text search), and by year of publication.
#
# Here's what you put in your Controller:
#
#   class BooksController < ApplicationController
#     def index
#       @filter_by = ListFilter.new(self)
#       @filter_by.filter_by(:author_id)
#       @filter_by.filter_by(:title, :sql => "title LIKE "%?%")
#       @filter_by.filter_by(:min_year_of_publication, :sql => "year >= ?")
#       @filter_by.filter_by(:max_year_of_publication, :sql => "year <= ?")
#
#       @books = Book.find(:all, :conditions => @filter_by.conditions)
#       @authors = Author.find(:all)
#     end
#   end
#
# And here's your view:
#
#   <% form_for(:filter_by, :html => {:method => :get}) do |f| %>
#     <dl>
#       <dt>Author:</dt>
#       <dd><%= f.select(:author_id) %></dd>
#
#       <dt>Title:</td>
#       <dd><%= f.text_field(:title)</dd>
#
#       <dt>Year of Publication:</dt>
#       <dd><%= f.text_field(:min_year_of_publication) %> to <%= f.text_field(:max_year_of_publication) %></dd>
#     </dl>
#
#     <%= f.submit("Filter")  %>
#   <% end %>
#
#   <table>
#     <thead>
#       <tr>
#         <th>Title</th><th>Author</th><th>Year</th>
#       </tr>
#     </thead>
#     <tbody>
#       <% @books.each do |book| %>
#         <tr>
#           <td><%= book.title %></td>
#           <td><%= book.author %></td>
#           <td><%= book.year %></td>
#         </tr>
#     </tbody>
#   </table>
#
# That's it. When the user clicks the "Filter" button, the ListFilter will
# process their filter options, store them in the session, and generate the
# appropriate SQL conditions.
#
# One thing to watch out for -- make sure that the name of your form in your view
# (<tt>form_for(:filter_by, </tt>...) corresponds to the variable name in your
# controller (<tt>@filter_by</tt>).
#
# Have a look at the #filter_by docs for details on the kinds of options
# you can specify.
class ListFilter
  # Adds sql constraints that will always be applied to the filter query, regardless of filter values.
  # Example: "group = 'foo'". This constraint will be appended to the rest of the filter query using AND.
  attr_accessor :constraints

  # Initialize the ListFilter. Needs access to the current controller, so
  # inside a controller action initialization will also look like this:
  #
  #   @filter_by = ListFilter.new(self)
  #
  # Where <tt>self</tt> is the current controller instance.
  def initialize(controller)
    controller.session[:filter_by] ||= {}
    @controller = controller

    @sql = ''
    @constraints = ''
    @values = []
    @values_hash = {}
  end

  # Sets up a filter for a particular field and parses the params given to this filter's controller.
  #
  # field:: The name of the field you'll be filtering. This must match the name you use in your view.
  #         Unless you specify a custom :sql option, this must also match the name of the field in the database.
  # options:: Options Hash. See below.
  #
  # Possible options are:
  #
  # [:sql]  ActiveRecord SQL condition. For example, "foo LIKE '%?%'". By default this is "#{field} = ?"
  # [:dont_retain_filter]   If true, filter settings will not be stored in the session. False by default.
  # [:default]  The default value to use for this field if the user does not specify anything. nil by default.
  def filter_by(field, options = {})
    session = @controller.session
    params = @controller.params
    
    path_key = @controller.url_for(:controller => @controller.controller_name, :action => params[:action], :only_path => true)

    val = session[:filter_by][field] && session[:filter_by][field][path_key] || options[:default]
    if params[:filter_by] && params[:filter_by].has_key?(field)
      if params[:filter_by][field].nil? || params[:filter_by][field].blank?
        val = nil
      elsif params[:filter_by][field].kind_of?(Array)
        val = params[:filter_by][field].dup.delete_if{|v| v.blank?}
      elsif params[:filter_by][field] =~ /^[0-9]+$/
        val = params[:filter_by][field].to_i
      elsif params[:filter_by][field]
        val = params[:filter_by][field]
      end

      unless params[:dont_retain_filter]
        session[:filter_by][field] ||= {}
        session[:filter_by][field][path_key] = val
      end
    end

    condition = nil

    if options[:sql]
      condition = options[:sql]
      if condition.include?('?')
        @values << val
        @values_hash[field] = val
      end
    elsif !val.nil?
      condition = "#{field} = ?"
      @values << val
      @values_hash[field] = val
    end

    if condition
      @sql << " AND " unless @sql.blank?
      @sql << condition
    end
  end

  # Returns the SQL conditions array, ready to be fed into an ActiveRecord#find call 
  # E.g.:
  #   Book.find(:all, :conditions => @filter_by.conditions)
  def conditions
    return "1" if no_conditions?
    sql = "(#{@sql})"
    sql << "AND (#{@constraints})" unless @constraints.blank?
    ["(#{sql})"] + @values
  end

  # Returns true if the filter has no conditions (i.e. the generated SQL
  # conditions would be blank).
  def no_conditions?
    @sql.blank?
  end


  # kludge for dealing with json_autocomplete...
  def []=(field, value) #:nodoc:
    @values_hash[field] = value
  end

  def method_missing(meth) #:nodoc:
    @values_hash[meth]
  end

  # this makes dom_id() happy
  def id #:nodoc:
    "filter"
  end
end
