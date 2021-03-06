$ = require('jquery')
Page = require('../../../src/rendering_container/page')
RenderingContainer = require('../../../src/rendering_container/rendering_container')
Design = require('../../../src/design/design')
ComponentTree = require('../../../src/component_tree/component_tree')
Renderer = require('../../../src/rendering/renderer')

module.exports = class InstanceInjector

  constructor: ->
    @instances = {}


  @get: (args...) ->
    injector = new InstanceInjector
    for arg in args
      injector.create(arg)

    injector.instances


  create: (name) ->
    return @instances[name] if @has(name)

    @instances[name] = switch name
      when 'renderer'
        new Renderer
          componentTree: @create('componentTree')
          renderingContainer: @requireContainer()

      when 'componentTree'
        new ComponentTree
          design: @create('design')

      when 'design'
        test.getDesign()

      when 'renderingContainer', 'page', 'interactivePage'
        @createContainer(name)



  createContainer: (name) ->
    @instances[name] = switch name
      when 'renderingContainer'
        new RenderingContainer()
      when 'page'
        new Page
          renderNode: @createRenderNode()
          design: @create('design', @instances)


  requireContainer: ->
    for containerName in ['renderingContainer', 'page', 'interactivePage']
      return @instances[containerName] if @has(containerName)

    log.error 'A container is required'


  has: (name) ->
    @instances[name]?


  createRenderNode: ->
    $('<section>')

