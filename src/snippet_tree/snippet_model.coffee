deepEqual = require('deep-equal')
config = require('../configuration/config')
SnippetContainer = require('./snippet_container')
guid = require('../modules/guid')
log = require('../modules/logging/log')
assert = require('../modules/logging/assert')
serialization = require('../modules/serialization')
directiveFactory = require('./snippet_directive_factory')

# SnippetModel
# ------------
# Each SnippetModel has a template which allows to generate a snippetView
# from a snippetModel
#
# Represents a node in a SnippetTree.
# Every SnippetModel can have a parent (SnippetContainer),
# siblings (other snippets) and multiple containers (SnippetContainers).
#
# The containers are the parents of the child SnippetModels.
# E.g. a grid row would have as many containers as it has
# columns
#
# # @prop parentContainer: parent SnippetContainer
module.exports = class SnippetModel

  constructor: ({ @template, id } = {}) ->
    assert @template, 'cannot instantiate snippet without template reference'

    @initializeDirectives()
    @styles = {}
    @dataValues = {}
    @id = id || guid.next()
    @identifier = @template.identifier

    @next = undefined # set by SnippetContainer
    @previous = undefined # set by SnippetContainer
    @snippetTree = undefined # set by SnippetTree


  initializeDirectives: ->
    for directive in @template.directives
      switch directive.type
        when 'container'
          @containers ||= {}
          @containers[directive.name] = new SnippetContainer
            name: directive.name
            parentSnippet: this
        when 'editable', 'image', 'html'
          @createSnippetDirective(directive)
          @content ||= {}
          @content[directive.name] = undefined
        else
          log.error "Template directive type '#{ directive.type }' not implemented in SnippetModel"


  # Create a directive for 'editable', 'image', 'html' template directives
  createSnippetDirective: (templateDirective) ->
    @directives ?= {}
    @directives[templateDirective.name] = directiveFactory.create
      snippet: this
      templateDirective: templateDirective


  createView: (isReadOnly) ->
    @template.createView(this, isReadOnly)


  # SnippetTree operations
  # ----------------------

  # Insert a snippet before this one
  before: (snippetModel) ->
    if snippetModel
      @parentContainer.insertBefore(this, snippetModel)
      this
    else
      @previous


  # Insert a snippet after this one
  after: (snippetModel) ->
    if snippetModel
      @parentContainer.insertAfter(this, snippetModel)
      this
    else
      @next


  # Append a snippet to a container of this snippet
  append: (containerName, snippetModel) ->
    if arguments.length == 1
      snippetModel = containerName
      containerName = config.directives.container.defaultName

    @containers[containerName].append(snippetModel)
    this


  # Prepend a snippet to a container of this snippet
  prepend: (containerName, snippetModel) ->
    if arguments.length == 1
      snippetModel = containerName
      containerName = config.directives.container.defaultName

    @containers[containerName].prepend(snippetModel)
    this


  # Move this snippet up (previous)
  up: ->
    @parentContainer.up(this)
    this


  # Move this snippet down (next)
  down: ->
    @parentContainer.down(this)
    this


  # Remove this snippet from its container and SnippetTree
  remove: ->
    @parentContainer.remove(this)


  # SnippetTree Iterators
  # ---------------------
  #
  # Navigate and query the snippet tree relative to this snippet.

  getParent: ->
     @parentContainer?.parentSnippet


  parents: (callback) ->
    snippetModel = this
    while (snippetModel = snippetModel.getParent())
      callback(snippetModel)


  children: (callback) ->
    for name, snippetContainer of @containers
      snippetModel = snippetContainer.first
      while (snippetModel)
        callback(snippetModel)
        snippetModel = snippetModel.next


  descendants: (callback) ->
    for name, snippetContainer of @containers
      snippetModel = snippetContainer.first
      while (snippetModel)
        callback(snippetModel)
        snippetModel.descendants(callback)
        snippetModel = snippetModel.next


  descendantsAndSelf: (callback) ->
    callback(this)
    @descendants(callback)


  # return all descendant containers (including those of this snippetModel)
  descendantContainers: (callback) ->
    @descendantsAndSelf (snippetModel) ->
      for name, snippetContainer of snippetModel.containers
        callback(snippetContainer)


  # return all descendant containers and snippets
  allDescendants: (callback) ->
    @descendantsAndSelf (snippetModel) =>
      callback(snippetModel) if snippetModel != this
      for name, snippetContainer of snippetModel.containers
        callback(snippetContainer)


  childrenAndSelf: (callback) ->
    callback(this)
    @children(callback)


  # Directive Operations
  # --------------------
  #
  # Example how to get an ImageDirective:
  # imageDirective = snippetModel.directives['image']

  hasContainers: ->
    @template.directives.count('container') > 0


  hasEditables: ->
    @template.directives.count('editable') > 0


  hasHtml: ->
    @template.directives.count('html') > 0


  hasImages: ->
    @template.directives.count('image') > 0


  # set the content data field of the snippet
  setContent: (name, value) ->
    if not value
      if @content[name]
        @content[name] = undefined
        @snippetTree.contentChanging(this, name) if @snippetTree
    else if typeof value == 'string'
      if @content[name] != value
        @content[name] = value
        @snippetTree.contentChanging(this, name) if @snippetTree
    else
      if not deepEqual(@content[name], value)
        @content[name] = value
        @snippetTree.contentChanging(this, name) if @snippetTree


  set: (name, value) ->
    assert @content?.hasOwnProperty(name),
      "set error: #{ @identifier } has no content named #{ name }"

    directive = @directives[name]
    if directive.isImage
      if directive.getImageUrl() != value
        directive.setImageUrl(value)
        @snippetTree.contentChanging(this, name) if @snippetTree
    else
      @setContent(name, value)


  get: (name) ->
    assert @content?.hasOwnProperty(name),
      "get error: #{ @identifier } has no content named #{ name }"

    @directives[name].getContent()


  # Check if a directive has content
  isEmpty: (name) ->
    value = @get(name)
    value == undefined || value == ''


  # Data Operations
  # ---------------
  #
  # Set arbitrary data to be stored with this snippetModel.


  # can be called with a string or a hash
  data: (arg) ->
    if typeof(arg) == 'object'
      changedDataProperties = []
      for name, value of arg
        if @changeData(name, value)
          changedDataProperties.push(name)
      if @snippetTree && changedDataProperties.length > 0
        @snippetTree.dataChanging(this, changedDataProperties)
    else
      @dataValues[arg]


  # @api private
  changeData: (name, value) ->
    if not deepEqual(@dataValues[name], value)
      @dataValues[name] = value
      true
    else
      false


  # Style Operations
  # ----------------

  getStyle: (name) ->
    @styles[name]


  setStyle: (name, value) ->
    style = @template.styles[name]
    if not style
      log.warn "Unknown style '#{ name }' in SnippetModel #{ @identifier }"
    else if not style.validateValue(value)
      log.warn "Invalid value '#{ value }' for style '#{ name }' in SnippetModel #{ @identifier }"
    else
      if @styles[name] != value
        @styles[name] = value
        if @snippetTree
          @snippetTree.htmlChanging(this, 'style', { name, value })


  # @deprecated
  # Getter and Setter in one.
  style: (name, value) ->
    console.log("SnippetModel#style() is deprecated. Please use #getStyle() and #setStyle().")
    if arguments.length == 1
      @styles[name]
    else
      @setStyle(name, value)


  # SnippetModel Operations
  # -----------------------

  copy: ->
    log.warn("SnippetModel#copy() is not implemented yet.")

    # serializing/deserializing should work but needs to get some tests first
    # json = @toJson()
    # json.id = guid.next()
    # SnippetModel.fromJson(json)


  copyWithoutContent: ->
    @template.createModel()


  # @api private
  destroy: ->
    # todo: move into to renderer

    # remove user interface elements
    @uiInjector.remove() if @uiInjector


  ui: ->
    if not @uiInjector
      @snippetTree.renderer.createInterfaceInjector(this)
    @uiInjector


  # Serialization
  # -------------

  toJson: ->

    json =
      id: @id
      identifier: @identifier

    unless serialization.isEmpty(@content)
      json.content = serialization.flatCopy(@content)

    unless serialization.isEmpty(@styles)
      json.styles = serialization.flatCopy(@styles)

    unless serialization.isEmpty(@dataValues)
      json.data = $.extend(true, {}, @dataValues)

    # create an array for every container
    for name of @containers
      json.containers ||= {}
      json.containers[name] = []

    json


SnippetModel.fromJson = (json, design) ->
  template = design.get(json.identifier)

  assert template,
    "error while deserializing snippet: unknown template identifier '#{ json.identifier }'"

  model = new SnippetModel({ template, id: json.id })

  for name, value of json.content
    assert model.content.hasOwnProperty(name),
      "error while deserializing snippet: unknown content '#{ name }'"

    # Transform string into object: Backwards compatibility for old image values.
    if model.directives[name].type == 'image' && typeof value == 'string'
      model.content[name] =
        url: value
    else
      model.content[name] = value

  for styleName, value of json.styles
    model.setStyle(styleName, value)

  model.data(json.data) if json.data

  for containerName, snippetArray of json.containers
    assert model.containers.hasOwnProperty(containerName),
      "error while deserializing snippet: unknown container #{ containerName }"

    if snippetArray
      assert $.isArray(snippetArray),
        "error while deserializing snippet: container is not array #{ containerName }"
      for child in snippetArray
        model.append( containerName, SnippetModel.fromJson(child, design) )

  model
