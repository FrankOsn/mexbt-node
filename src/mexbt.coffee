request = require 'request'
crypto = require 'crypto'
RobustWebSocket = require './robust_web_socket'
{EventEmitter} = require 'events'

class Mexbt extends EventEmitter
  publicEndpoint: "https://public-api.mexbt.com"
  privateEndpoint: null

  constructor: (@key, @secret, @userId, options={}) ->
    @privateEndpoint = "https://private-api#{if options?.sandbox? then '-sandbox' else ''}.mexbt.com"

  subscribeToStream: (pair='btcmxn') ->
    @socket = new RobustWebSocket('wss://api.mexbt.com:8401/v1/GetL2AndTrades/', (socket) =>
      socket.send(JSON.stringify({ins: pair}))
    , (data) =>
      json = JSON.parse(data)
      for tradeOrOrder in json
        @parseStreamApiMessage(tradeOrOrder)
    )

  # Public API functions

  ticker: (args...) ->
    [params, callback] = @_parseArgs(args)
    params = @_mergeDefaultsAndRewrite(params, {pair: 'btcmxn'}, {pair: 'productPair'})
    @_public('ticker', params, callback)

  trades: (args...) ->
    [params, callback] = @_parseArgs(args)
    params = @_mergeDefaultsAndRewrite(params, {pair: 'btcmxn', startIndex: -1, count: 20}, {pair: 'ins'})
    @_public('trades', params, callback)

  tradesByDate: (params, callback) ->
    params = @_mergeDefaultsAndRewrite(params, {pair: 'btcmxn'}, {pair: 'ins'})
    @_public('trades-by-date', params, callback)

  orderBook: (args...) ->
    [params, callback] = @_parseArgs(args)
    params = @_mergeDefaultsAndRewrite(params, {pair: 'btcmxn'}, {pair: 'productPair'})
    @_public('order-book', params, callback)

  productPairs: (callback) ->
    @_public('product-pairs', {}, callback)

  # Private API functions

  accountInfo: (callback) ->
    @_private('me', {}, callback)

  accountBalance: (callback) ->
    @_private('balance', {}, callback)

  accountTrades: (args...) ->
    [params, callback] = @_parseArgs(args)
    params = @_mergeDefaultsAndRewrite(params, {pair: 'btcmxn', startIndex: -1, count: 20}, {pair: 'ins'})
    @_private('trades', params, callback)

  accountTradingFee: (args...) ->
    [params, callback] = @_parseArgs(args)
    params = @_mergeDefaultsAndRewrite(params, {pair: 'btcmxn', type: 'market', side: 'buy', price: null}, {amount: 'qty', price: 'px', pair: 'ins', type: 'orderType'})
    if params.orderType is 'market'
      params.orderType = 1
    else
      params.orderType = 0
    @_private('trading-fee', params, callback)

  accountOrders: (callback) ->
    @_private('orders', {}, callback)

  accountDepositAddresses: (callback) ->
    @_private('deposit-addresses', {}, callback)

  withdraw: (params, callback) ->
    params = @_mergeDefaultsAndRewrite(params, {currency: 'btc'}, {currency: 'ins'})
    @_private('withdraw', params, callback)

  createOrder: (params, callback) ->
    params = @_mergeDefaultsAndRewrite(params, {pair: 'btcmxn', side: 'buy', type: 'market'}, {pair: 'ins', amount: 'qty', price: 'px', type: 'orderType'})
    if params.orderType is 'market'
      params.orderType = 1
    else
      params.orderType = 0
    @_private('orders/create', params, callback)

  modifyOrder: (params, callback) ->
    params = @_mergeDefaultsAndRewrite(params, {pair: 'btcmxn'}, {id: 'serverOrderId', pair: 'ins', action: 'modifyAction'})
    switch params.modifyAction
      when 'move_to_top'
        params.modifyAction = 0
      when 'execute_now'
        params.modifyAction = 1
      else
        throw "You must specify an action parameter with either 'move_to_top' or 'execute_now'"
    @_private('orders/modify', params, callback)

  cancelOrder: (params, callback) ->
    params = @_mergeDefaultsAndRewrite(params, {pair: 'btcmxn'}, {id: 'serverOrderId', pair: 'ins'})
    @_private('orders/cancel', params, callback)

  cancelAllOrders: (args...) ->
    [params, callback] = @_parseArgs(args)
    params = @_mergeDefaultsAndRewrite(params, {pair: 'btcmxn'}, {pair: 'ins'})
    @_private('orders/cancel-all', params, callback)

  # Helper functions

  parseStreamApiMessage: (tradeOrOrder) ->
    [id, tick, price, quantity, action, side] = tradeOrOrder
    date = tick2UnixTimestamp(tick)
    sideString = if side is 0 then 'buy' else 'sell'
    obj = {id: id, date: date, price: price, quantity: quantity, side: sideString}
    if action is 0
      if quantity is 0
        @emit('order-removed', obj)
      else
        @emit('order', obj)
    else
      @emit('trade', obj)

  tick2UnixTimestamp = (tick) ->
    parseInt((tick - 621355968000000000) / 10000000)

  _private: (path, params, callback) ->
    nonce = (new Date()).getTime()
    message = "#{nonce}#{@userId}#{@key}"
    signature = crypto.createHmac("sha256", @secret).update(message).digest('hex').toUpperCase()
    params.apiKey = @key
    params.apiNonce = nonce
    params.apiSig = signature
    @_call(@_url(@privateEndpoint, path), params, callback)

  _public: (path, params, callback) ->
    @_call(@_url(@publicEndpoint, path), params, callback)

  _url: (endpoint, path) ->
    "#{endpoint}/v1/#{path}"

  _call: (url, params, callback) ->
    request.post({
      url: url
      json: true,
      body: params
    }, (err, res, body) ->
      if err or !body?.isAccepted
        callback(err || "API Error: #{body.rejectReason}")
      else
        callback(null, body)
    )

  _mergeDefaultsAndRewrite: (params, defaults, rewriteInfo={}) ->
    for key, value of defaults
      unless params[key]
        params[key] = value
    for key, value of rewriteInfo
      params[value] = params[key]
      delete params[key]
    params

  _parseArgs: (args) ->
    if args[1]
      args
    else
      [{}, args[0]]


module.exports = Mexbt
