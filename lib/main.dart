import 'package:flutter/material.dart';
import 'services/google_sheets_service.dart';

void main() {
  runApp(const VentasApp());
}

class VentasApp extends StatelessWidget {
  const VentasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ventas Sport PDF',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F6FA),
      ),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;

  final GoogleSheetsService _sheetsService = GoogleSheetsService();

  // Datos globales cargados desde Google Sheets
  List<Map<String, dynamic>> _clientes = [];
  List<Map<String, dynamic>> _productos = [];
  List<Map<String, dynamic>> _pedidosGuardados = [];

  bool _cargandoDatos = false;

  @override
  void initState() {
    super.initState();
    _cargarDatosIniciales();
  }

  Future<void> _cargarDatosIniciales() async {
    setState(() => _cargandoDatos = true);
    try {
      final clientesData = await _sheetsService.getClientes();
      final productosData = await _sheetsService.getProductos();

      setState(() {
        _clientes = clientesData;
        _productos = productosData;
        _cargandoDatos = false;
      });
    } catch (e) {
      setState(() => _cargandoDatos = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar datos iniciales: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> paginas = [
      _buildTabClientes(),
      _buildTabProductos(),
      _buildTabCrearPedido(),
      _buildTabHistorialPedidos(),
      _buildTabExportarPdf(),
      _buildTabConfiguracion(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Ventas Sport PDF',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar Datos',
            onPressed: _cargarDatosIniciales,
          ),
        ],
      ),
      body: _cargandoDatos
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Cargando clientes y productos...'),
                ],
              ),
            )
          : IndexedStack(
              index: _selectedIndex,
              children: paginas,
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.indigo,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Clientes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2),
            label: 'Productos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_shopping_cart),
            label: 'Crear Pedido',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: 'Pedidos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.picture_as_pdf),
            label: 'Exportar PDF',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }

  // ==========================================
  // PESTAÑA 1: CLIENTES
  // ==========================================
  Widget _buildTabClientes() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Directorio de Clientes (${_clientes.length})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _clientes.isEmpty
                ? const Center(child: Text('No hay clientes disponibles'))
                : ListView.builder(
                    itemCount: _clientes.length,
                    itemBuilder: (context, index) {
                      final c = _clientes[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              (c['nombre'] != null && c['nombre'].toString().isNotEmpty)
                                  ? c['nombre'].toString()[0].toUpperCase()
                                  : 'C',
                            ),
                          ),
                          title: Text(c['nombre'] ?? 'Sin Nombre'),
                          subtitle: Text('Tel: ${c['telefono']} | Dir: ${c['direccion']}'),
                          trailing: Text('ID: ${c['id']}'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // PESTAÑA 2: PRODUCTOS
  // ==========================================
  Widget _buildTabProductos() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Catálogo de Productos (${_productos.length})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _productos.isEmpty
                ? const Center(child: Text('No hay productos disponibles'))
                : ListView.builder(
                    itemCount: _productos.length,
                    itemBuilder: (context, index) {
                      final p = _productos[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: const Icon(Icons.shopping_bag, color: Colors.indigo),
                          title: Text(p['nombre'] ?? 'Sin Nombre'),
                          subtitle: Text('Stock: ${p['stock']} unidades'),
                          trailing: Text(
                            'L. ${(p['precio'] ?? 0.0).toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // PESTAÑA 3: CREAR PEDIDO (CON BUSCADORES)
  // ==========================================
  Map<String, dynamic>? _clienteSeleccionado;
  final List<Map<String, dynamic>> _itemsPedido = [];
  bool _guardandoPedido = false;

  Widget _buildTabCrearPedido() {
    double subtotal = 0;
    for (var item in _itemsPedido) {
      subtotal += (item['precio'] * item['cantidad']);
    }
    double isv = subtotal * 0.15;
    double total = subtotal + isv;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nuevo Pedido',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Seleccionar Cliente
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Cliente:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          _clienteSeleccionado == null
                              ? 'Ningún cliente seleccionado'
                              : '${_clienteSeleccionado!['nombre']} (${_clienteSeleccionado!['telefono']})',
                          style: TextStyle(
                            color: _clienteSeleccionado == null ? Colors.red : Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _abrirBuscadorCliente,
                    icon: const Icon(Icons.search),
                    label: const Text('Buscar'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Agregar Productos
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Items del Pedido:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ElevatedButton.icon(
                onPressed: _abrirBuscadorProducto,
                icon: const Icon(Icons.add),
                label: const Text('Agregar Producto'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Lista de Items Agregados
          _itemsPedido.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('No has agregado productos al pedido.')),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _itemsPedido.length,
                  itemBuilder: (context, index) {
                    final item = _itemsPedido[index];
                    return Card(
                      child: ListTile(
                        title: Text(item['nombre']),
                        subtitle: Text('Cant: ${item['cantidad']} x L. ${item['precio']}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'L. ${(item['precio'] * item['cantidad']).toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  _itemsPedido.removeAt(index);
                                });
                              },
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),

          const Divider(height: 30),

          // Resumen de Totales
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Subtotal:'),
                    Text('L. ${subtotal.toStringAsFixed(2)}'),
                  ]),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('ISV (15%):'),
                    Text('L. ${isv.toStringAsFixed(2)}'),
                  ]),
                  const Divider(),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('TOTAL:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    Text('L. ${total.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo)),
                  ]),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Botón Guardar Pedido
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              icon: _guardandoPedido
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white))
                  : const Icon(Icons.cloud_upload),
              label: Text(_guardandoPedido ? 'Guardando...' : 'GUARDAR PEDIDO EN GOOGLE SHEETS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              onPressed: _guardandoPedido ? null : _enviarPedido,
            ),
          ),
        ],
      ),
    );
  }

  // Modal de Búsqueda de Clientes
  void _abrirBuscadorCliente() {
    String filtro = '';
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final listaFiltrada = _clientes.where((c) {
              final nombre = (c['nombre'] ?? '').toString().toLowerCase();
              return nombre.contains(filtro.toLowerCase());
            }).toList();

            return AlertDialog(
              title: const Text('Buscar Cliente'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Escribe para buscar...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (val) {
                        setModalState(() => filtro = val);
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: listaFiltrada.length,
                        itemBuilder: (context, index) {
                          final c = listaFiltrada[index];
                          return ListTile(
                            title: Text(c['nombre'] ?? ''),
                            subtitle: Text(c['telefono'] ?? ''),
                            onTap: () {
                              setState(() => _clienteSeleccionado = c);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar'),
                )
              ],
            );
          },
        );
      },
    );
  }

  // Modal de Búsqueda de Productos
  void _abrirBuscadorProducto() {
    String filtro = '';
    int cantidad = 1;
    Map<String, dynamic>? prodSeleccionado;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final listaFiltrada = _productos.where((p) {
              final nombre = (p['nombre'] ?? '').toString().toLowerCase();
              return nombre.contains(filtro.toLowerCase());
            }).toList();

            return AlertDialog(
              title: const Text('Seleccionar Producto'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Nombre de producto...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (val) {
                        setModalState(() => filtro = val);
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: listaFiltrada.length,
                        itemBuilder: (context, index) {
                          final p = listaFiltrada[index];
                          final seleccionado = prodSeleccionado == p;
                          return ListTile(
                            tileColor: seleccionado ? Colors.indigo.shade50 : null,
                            title: Text(p['nombre'] ?? ''),
                            subtitle: Text('Precio: L. ${p['precio']}'),
                            onTap: () {
                              setModalState(() => prodSeleccionado = p);
                            },
                          );
                        },
                      ),
                    ),
                    if (prodSeleccionado != null) ...[
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Cantidad: '),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: cantidad > 1 ? () => setModalState(() => cantidad--) : null,
                          ),
                          Text('$cantidad', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => setModalState(() => cantidad++),
                          ),
                        ],
                      )
                    ]
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: prodSeleccionado == null
                      ? null
                      : () {
                          setState(() {
                            _itemsPedido.add({
                              'id': prodSeleccionado!['id'],
                              'nombre': prodSeleccionado!['nombre'],
                              'precio': prodSeleccionado!['precio'],
                              'cantidad': cantidad,
                            });
                          });
                          Navigator.pop(context);
                        },
                  child: const Text('Agregar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Guardar/Enviar Pedido
  Future<void> _enviarPedido() async {
    if (_clienteSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor selecciona un cliente.')),
      );
      return;
    }

    if (_itemsPedido.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un producto al pedido.')),
      );
      return;
    }

    setState(() => _guardandoPedido = true);

    double subtotal = 0;
    for (var item in _itemsPedido) {
      subtotal += (item['precio'] * item['cantidad']);
    }

    final payload = {
      'cliente': _clienteSeleccionado!['nombre'],
      'telefono': _clienteSeleccionado!['telefono'],
      'items': _itemsPedido,
      'total': subtotal * 1.15,
      'fecha': DateTime.now().toIso8601String(),
    };

    final exito = await _sheetsService.guardarPedido(payload);

    setState(() => _guardandoPedido = false);

    if (exito) {
      _pedidosGuardados.add(payload);
      setState(() {
        _itemsPedido.clear();
        _clienteSeleccionado = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Pedido guardado exitosamente en Google Sheets!'), backgroundColor: Colors.green),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al enviar el pedido. Intenta de nuevo.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ==========================================
  // PESTAÑA 4: HISTORIAL DE PEDIDOS
  // ==========================================
  Widget _buildTabHistorialPedidos() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pedidos Registrados (${_pedidosGuardados.length})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _pedidosGuardados.isEmpty
                ? const Center(child: Text('No se han guardado pedidos en esta sesión.'))
                : ListView.builder(
                    itemCount: _pedidosGuardados.length,
                    itemBuilder: (context, index) {
                      final p = _pedidosGuardados[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.receipt, color: Colors.green),
                          title: Text('Cliente: ${p['cliente']}'),
                          subtitle: Text('Items: ${(p['items'] as List).length} productos'),
                          trailing: Text(
                            'L. ${(p['total'] as double).toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // PESTAÑA 5: EXPORTAR PDF
  // ==========================================
  Widget _buildTabExportarPdf() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.picture_as_pdf, size: 80, color: Colors.indigo),
          SizedBox(height: 16),
          Text(
            'Módulo Exportar PDF',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text('Los reportes y facturas PDF se generarán directamente aquí.'),
        ],
      ),
    );
  }

  // ==========================================
  // PESTAÑA 6: CONFIGURACIÓN
  // ==========================================
  Widget _buildTabConfiguracion() {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        const Text(
          'Ajustes de la Aplicación',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Estado de la Conexión'),
          subtitle: const Text('Conectado a Google Sheets por CSV directo'),
          trailing: const Icon(Icons.check_circle, color: Colors.green),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Versión de la App'),
          subtitle: const Text('v1.0.0 (Sport PDF Edition)'),
        ),
      ],
    );
  }
}
