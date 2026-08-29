import 'google_sheets_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// --- CONFIGURACIÓN DE GOOGLE SHEETS ---
const String googleSheetsWebAppUrl = "https://script.google.com/macros/s/AKfycbzu5c_K_fX9uEhqs-B9co3cCpex8i4vQu8wuwvtMdUP03Jf5IzShNPKNWMEW2zsStmx/exec";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppVentasExportPdf());
}

class AppVentasExportPdf extends StatelessWidget {
  const AppVentasExportPdf({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Ventas ExportPdf',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const MainNavigationScreen(),
    );
  }
}

// --- MODELOS DE DATOS ---
class Cliente {
  final String codigo;
  final String nombre;
  final String telefono;

  Cliente({required this.codigo, required this.nombre, required this.telefono});

  factory Cliente.fromList(List<dynamic> list) {
    return Cliente(
      codigo: list.isNotEmpty ? list[0].toString() : '',
      nombre: list.length > 1 ? list[1].toString() : '',
      telefono: list.length > 2 ? list[2].toString() : '',
    );
  }
}

class Producto {
  final String codigo;
  final String nombre;
  final double precio;

  Producto({required this.codigo, required this.nombre, required this.precio});

  factory Producto.fromList(List<dynamic> list) {
    double parsedPrecio = 0.0;
    if (list.length > 2) {
      String rawPrecio = list[2].toString().replaceAll('L', '').replaceAll(',', '').trim();
      parsedPrecio = double.tryParse(rawPrecio) ?? 0.0;
    }
    return Producto(
      codigo: list.isNotEmpty ? list[0].toString() : '',
      nombre: list.length > 1 ? list[1].toString() : '',
      precio: parsedPrecio,
    );
  }
}

class ItemPedido {
  final Producto producto;
  int cantidad;

  ItemPedido({required this.producto, this.cantidad = 1});

  double get subtotal => producto.precio * cantidad;
}

class Pedido {
  String numeroPedido;
  Cliente cliente;
  List<ItemPedido> productos;
  DateTime fechaCreacion;

  Pedido({
    required this.numeroPedido,
    required this.cliente,
    required this.productos,
    required this.fechaCreacion,
  });

  double get total => productos.fold(0.0, (sum, item) => sum + item.subtotal);
}

// --- PANTALLA PRINCIPAL DE NAVEGACIÓN ---
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  int _contadorPedidos = 1;

  List<Cliente> _clientes = [];
  List<Producto> _productos = [];
  List<Pedido> _historialPedidos = [];
  bool _cargandoDatos = false;

  Cliente? _clienteSeleccionado;
  List<ItemPedido> _carritoActual = [];

  final NumberFormat _formatoLempiras = NumberFormat.currency(symbol: 'L ', decimalDigits: 2);
  final DateFormat _formatoFecha = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _cargarContador();
    _cargarDatosGoogleSheets();
  }

  Future<void> _cargarContador() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _contadorPedidos = prefs.getInt('contador_pedidos') ?? 1;
    });
  }

  Future<void> _guardarContador(int val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('contador_pedidos', val);
  }

  Future<void> _cargarDatosGoogleSheets() async {
    if (googleSheetsWebAppUrl == "TU_URL_DE_GOOGLE_APPS_SCRIPT_AQUI") {
      _cargarDatosDemo();
      return;
    }

    setState(() => _cargandoDatos = true);
    try {
      final resClientes = await http.get(Uri.parse('$googleSheetsWebAppUrl?sheet=Clientes'));
      final resProductos = await http.get(Uri.parse('$googleSheetsWebAppUrl?sheet=Productos'));

      if (resClientes.statusCode == 200 && resProductos.statusCode == 200) {
        List<dynamic> jsonClientes = json.decode(resClientes.body);
        List<dynamic> jsonProductos = json.decode(resProductos.body);

        if (jsonClientes.isNotEmpty) jsonClientes.removeAt(0);
        if (jsonProductos.isNotEmpty) jsonProductos.removeAt(0);

        setState(() {
          _clientes = jsonClientes.map((c) => Cliente.fromList(c)).toList();
          _productos = jsonProductos.map((p) => Producto.fromList(p)).toList();
        });
      } else {
        _cargarDatosDemo();
      }
    } catch (e) {
      _cargarDatosDemo();
    } finally {
      setState(() => _cargandoDatos = false);
    }
  }

  void _cargarDatosDemo() {
    setState(() {
      _clientes = [
        Cliente(codigo: "C001", nombre: "Comercial Honduras", telefono: "50499887766"),
        Cliente(codigo: "C002", nombre: "Distribuidora San Pedro", telefono: "50488776655"),
        Cliente(codigo: "C003", nombre: "Inversiones del Sur", telefono: "50433221100"),
      ];

      _productos = [
        Producto(codigo: "P001", nombre: "Producto Alfa Premium", precio: 1500.00),
        Producto(codigo: "P002", nombre: "Caja de Herramientas", precio: 850.50),
        Producto(codigo: "P003", nombre: "Set de Accesorios", precio: 320.00),
        Producto(codigo: "P004", nombre: "Lote Industrial Base", precio: 4500.00),
      ];
    });
  }

  void _resetearContador() {
    setState(() {
      _contadorPedidos = 1;
    });
    _guardarContador(1);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contador de pedidos reiniciado a #01')),
    );
  }

  void _guardarPedidoActual() {
    if (_clienteSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor seleccione un cliente')),
      );
      return;
    }
    if (_carritoActual.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agregue al menos un producto al pedido')),
      );
      return;
    }

    String numFormateado = "Pedido #${_contadorPedidos.toString().padLeft(2, '0')}";

    Pedido nuevoPedido = Pedido(
      numeroPedido: numFormateado,
      cliente: _clienteSeleccionado!,
      productos: List.from(_carritoActual),
      fechaCreacion: DateTime.now(),
    );

    setState(() {
      _historialPedidos.add(nuevoPedido);
      _contadorPedidos = (_contadorPedidos % 99) + 1;
      _clienteSeleccionado = null;
      _carritoActual.clear();
    });

    _guardarContador(_contadorPedidos);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$numFormateado guardado con éxito')),
    );
  }

  void _enviarWhatsApp(Pedido pedido) async {
    String telefono = pedido.cliente.telefono.replaceAll(RegExp(r'\D'), '');
    if (telefono.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El cliente no tiene teléfono válido')),
      );
      return;
    }

    StringBuffer mensaje = StringBuffer();
    mensaje.writeln("Hola *${pedido.cliente.nombre}*, adjuntamos el resumen de su *${pedido.numeroPedido}*:");
    mensaje.writeln("--------------------------------");
    for (var item in pedido.productos) {
      mensaje.writeln("${item.cantidad}x ${item.producto.nombre} - ${_formatoLempiras.format(item.subtotal)}");
    }
    mensaje.writeln("--------------------------------");
    mensaje.writeln("*Total:* ${_formatoLempiras.format(pedido.total)}");
    mensaje.writeln("Fecha: ${_formatoFecha.format(pedido.fechaCreacion)}");

    final url = Uri.parse("https://wa.me/$telefono?text=${Uri.encodeComponent(mensaje.toString())}");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp')),
      );
    }
  }

  void _mostrarOpcionesEdicion(Pedido pedido, int index) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.blue),
            title: const Text('Editar Pedido (Cliente / Productos)'),
            onTap: () {
              Navigator.pop(ctx);
              _editarPedidoDialog(pedido, index);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Eliminar Pedido'),
            onTap: () {
              Navigator.pop(ctx);
              setState(() {
                _historialPedidos.removeAt(index);
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${pedido.numeroPedido} eliminado')),
              );
            },
          ),
        ],
      ),
    );
  }

  void _editarPedidoDialog(Pedido pedido, int index) {
    Cliente clienteEditado = pedido.cliente;
    List<ItemPedido> productosEditados = List.from(pedido.productos);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Editar ${pedido.numeroPedido}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<Cliente>(
                  isExpanded: true,
                  value: clienteEditado,
                  items: _clientes
                      .map((c) => DropdownMenuItem(value: c, child: Text(c.nombre)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => clienteEditado = val);
                  },
                ),
                const Divider(),
                const Text('Productos del Pedido:', style: TextStyle(fontWeight: FontWeight.bold)),
                ...productosEditados.map((item) => Row(
                      children: [
                        Expanded(child: Text(item.producto.nombre)),
                        IconButton(
                          icon: const Icon(Icons.remove_circle, color: Colors.red),
                          onPressed: () {
                            setDialogState(() {
                              if (item.cantidad > 1) {
                                item.cantidad--;
                              } else {
                                productosEditados.remove(item);
                              }
                            });
                          },
                        ),
                        Text('${item.cantidad}'),
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: Colors.green),
                          onPressed: () {
                            setDialogState(() => item.cantidad++);
                          },
                        ),
                      ],
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _historialPedidos[index].cliente = clienteEditado;
                  _historialPedidos[index].productos = productosEditados;
                });
                Navigator.pop(ctx);
              },
              child: const Text('Guardar Cambios'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> pantallas = [
      _buildPestanaCrearPedido(),
      _buildPestanaHistorial(),
      _buildPestanaClientes(),
      _buildPestanaProductos(),
      _buildPestanaResumenGeneral(),
      _buildPestanaResumenProductos(),
      _buildPestanaExportarPdf(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Ventas ExportPdf'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarDatosGoogleSheets,
            tooltip: 'Sincronizar Sheets',
          ),
        ],
      ),
      body: _cargandoDatos
          ? const Center(child: CircularProgressIndicator())
          : pantallas[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.indigo,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.add_shopping_cart), label: 'Crear'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Historial'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Clientes'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: 'Productos'),
          BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Resumen'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Prod. Res'),
          BottomNavigationBarItem(icon: Icon(Icons.picture_as_pdf), label: 'PDF'),
        ],
      ),
    );
  }

  Widget _buildPestanaCrearPedido() {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            _BuscadorClienteWidget(
              clientes: _clientes,
              clienteSeleccionado: _clienteSeleccionado,
              onClienteSeleccionado: (cliente) {
                setState(() => _clienteSeleccionado = cliente);
              },
            ),
            const SizedBox(height: 10),
            _BuscadorProductoWidget(
              productos: _productos,
              onProductoAgregado: (producto) {
                setState(() {
                  int idx = _carritoActual.indexWhere((i) => i.producto.codigo == producto.codigo);
                  if (idx >= 0) {
                    _carritoActual[idx].cantidad++;
                  } else {
                    _carritoActual.add(ItemPedido(producto: producto));
                  }
                });
              },
            ),
            const Divider(height: 20),
            Expanded(
              child: _carritoActual.isEmpty
                  ? const Center(child: Text('Seleccione cliente y productos para el pedido'))
                  : ListView.builder(
                      itemCount: _carritoActual.length,
                      itemBuilder: (ctx, i) {
                        final item = _carritoActual[i];
                        return ListTile(
                          title: Text(item.producto.nombre),
                          subtitle: Text('Precio: ${_formatoLempiras.format(item.producto.precio)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove),
                                onPressed: () {
                                  setState(() {
                                    if (item.cantidad > 1) {
                                      item.cantidad--;
                                    } else {
                                      _carritoActual.removeAt(i);
                                    }
                                  });
                                },
                              ),
                              Text('${item.cantidad}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: () {
                                  setState(() => item.cantidad++);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.grey.shade100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total: ${_formatoLempiras.format(_carritoActual.fold(0.0, (sum, i) => sum + i.subtotal))}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.save),
                    label: const Text('Guardar Pedido'),
                    onPressed: _guardarPedidoActual,
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPestanaHistorial() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Pedidos: ${_historialPedidos.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                icon: const Icon(Icons.restart_alt),
                label: const Text('Resetear Conteo (#01)'),
                onPressed: _resetearContador,
              ),
            ],
          ),
        ),
        Expanded(
          child: _historialPedidos.isEmpty
              ? const Center(child: Text('No hay pedidos en el historial'))
              : ListView.builder(
                  itemCount: _historialPedidos.length,
                  itemBuilder: (ctx, i) {
                    final pedido = _historialPedidos[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        title: Text('${pedido.numeroPedido} - ${pedido.cliente.nombre}'),
                        subtitle: Text(
                            'Fecha: ${_formatoFecha.format(pedido.fechaCreacion)}\nTotal: ${_formatoLempiras.format(pedido.total)}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.send, color: Colors.green),
                          onPressed: () => _enviarWhatsApp(pedido),
                          tooltip: 'Enviar vía WhatsApp',
                        ),
                        onTap: () => _mostrarOpcionesEdicion(pedido, i),
                      ),
                    );
                  },
                ),
        )
      ],
    );
  }

  Widget _buildPestanaClientes() {
    return ListView.builder(
      itemCount: _clientes.length,
      itemBuilder: (ctx, i) {
        final c = _clientes[i];
        return ListTile(
          leading: CircleAvatar(child: Text(c.codigo)),
          title: Text(c.nombre),
          subtitle: Text('Teléfono: ${c.telefono}'),
        );
      },
    );
  }

  Widget _buildPestanaProductos() {
    return ListView.builder(
      itemCount: _productos.length,
      itemBuilder: (ctx, i) {
        final p = _productos[i];
        return ListTile(
          leading: CircleAvatar(child: Text(p.codigo)),
          title: Text(p.nombre),
          trailing: Text(_formatoLempiras.format(p.precio),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        );
      },
    );
  }

  Widget _buildPestanaResumenGeneral() {
    double ventaTotal = _historialPedidos.fold(0.0, (sum, p) => sum + p.total);
    Map<String, double> ventasPorCliente = {};

    for (var p in _historialPedidos) {
      ventasPorCliente[p.cliente.nombre] = (ventasPorCliente[p.cliente.nombre] ?? 0.0) + p.total;
    }

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.indigo.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Venta Acumulada Total:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(_formatoLempiras.format(ventaTotal),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),
          const Text('Ventas por Cliente:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Expanded(
            child: ListView(
              children: ventasPorCliente.entries
                  .map((e) => ListTile(
                        title: Text(e.key),
                        trailing: Text(_formatoLempiras.format(e.value)),
                      ))
                  .toList(),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPestanaResumenProductos() {
    Map<String, Map<String, dynamic>> resumen = {};

    for (var p in _historialPedidos) {
      for (var item in p.productos) {
        String prodNombre = item.producto.nombre;
        if (!resumen.containsKey(prodNombre)) {
          resumen[prodNombre] = {'unidades': 0, 'total': 0.0};
        }
        resumen[prodNombre]!['unidades'] += item.cantidad;
        resumen[prodNombre]!['total'] += item.subtotal;
      }
    }

    return ListView(
      children: resumen.entries.map((e) {
        return ListTile(
          title: Text(e.key),
          subtitle: Text('Unidades vendidas: ${e.value['unidades']}'),
          trailing: Text(_formatoLempiras.format(e.value['total']),
              style: const TextStyle(fontWeight: FontWeight.bold)),
        );
      }).toList(),
    );
  }

  Widget _buildPestanaExportarPdf() {
    return ExportarPdfScreen(
      historialPedidos: _historialPedidos,
      formatoLempiras: _formatoLempiras,
      formatoFecha: _formatoFecha,
    );
  }
}

class _BuscadorClienteWidget extends StatefulWidget {
  final List<Cliente> clientes;
  final Cliente? clienteSeleccionado;
  final Function(Cliente) onClienteSeleccionado;

  const _BuscadorClienteWidget({
    required this.clientes,
    required this.clienteSeleccionado,
    required this.onClienteSeleccionado,
  });

  @override
  State<_BuscadorClienteWidget> createState() => _BuscadorClienteWidgetState();
}

class _BuscadorClienteWidgetState extends State<_BuscadorClienteWidget> {
  final TextEditingController _controller = TextEditingController();
  List<Cliente> _filtrados = [];

  @override
  void initState() {
    super.initState();
    _filtrados = widget.clientes;
  }

  void _filtrar(String query) {
    setState(() {
      _filtrados = widget.clientes
          .where((c) => c.nombre.toLowerCase().contains(query.toLowerCase()) || c.codigo.contains(query))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: 'Buscar Cliente (Nombre o Código)',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: widget.clienteSeleccionado != null
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                      _filtrar('');
                    },
                  )
                : null,
            border: const OutlineInputBorder(),
          ),
          onChanged: _filtrar,
        ),
        if (_controller.text.isNotEmpty && widget.clienteSeleccionado == null)
          Container(
            height: 120,
            color: Colors.white,
            child: ListView.builder(
              itemCount: _filtrados.length,
              itemBuilder: (ctx, i) {
                final c = _filtrados[i];
                return ListTile(
                  title: Text(c.nombre),
                  onTap: () {
                    widget.onClienteSeleccionado(c);
                    _controller.text = c.nombre;
                    FocusScope.of(context).unfocus();
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

class _BuscadorProductoWidget extends StatefulWidget {
  final List<Producto> productos;
  final Function(Producto) onProductoAgregado;

  const _BuscadorProductoWidget({
    required this.productos,
    required this.onProductoAgregado,
  });

  @override
  State<_BuscadorProductoWidget> createState() => _BuscadorProductoWidgetState();
}

class _BuscadorProductoWidgetState extends State<_BuscadorProductoWidget> {
  final TextEditingController _controller = TextEditingController();
  List<Producto> _filtrados = [];

  @override
  void initState() {
    super.initState();
    _filtrados = widget.productos;
  }

  void _filtrar(String query) {
    setState(() {
      _filtrados = widget.productos
          .where((p) => p.nombre.toLowerCase().contains(query.toLowerCase()) || p.codigo.contains(query))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          decoration: const InputDecoration(
            labelText: 'Buscar Producto',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: _filtrar,
        ),
        if (_controller.text.isNotEmpty)
          Container(
            height: 120,
            color: Colors.white,
            child: ListView.builder(
              itemCount: _filtrados.length,
              itemBuilder: (ctx, i) {
                final p = _filtrados[i];
                return ListTile(
                  title: Text(p.nombre),
                  trailing: Icon(Icons.add_shopping_cart, color: Colors.indigo.shade400),
                  onTap: () {
                    widget.onProductoAgregado(p);
                    FocusScope.of(context).unfocus();
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

class ExportarPdfScreen extends StatefulWidget {
  final List<Pedido> historialPedidos;
  final NumberFormat formatoLempiras;
  final DateFormat formatoFecha;

  const ExportarPdfScreen({
    super.key,
    required this.historialPedidos,
    required this.formatoLempiras,
    required this.formatoFecha,
  });

  @override
  State<ExportarPdfScreen> createState() => _ExportarPdfScreenState();
}

class _ExportarPdfScreenState extends State<ExportarPdfScreen> {
  DateTime? _fechaInicio;
  DateTime? _fechaFin;
  String _numPedidoDesde = '';
  String _numPedidoHasta = '';

  List<Pedido> _filtrarPedidos() {
    return widget.historialPedidos.where((p) {
      bool coincideFecha = true;
      if (_fechaInicio != null && _fechaFin != null) {
        coincideFecha = p.fechaCreacion.isAfter(_fechaInicio!) &&
            p.fechaCreacion.isBefore(_fechaFin!.add(const Duration(days: 1)));
      }

      bool coincideRangoNum = true;
      if (_numPedidoDesde.isNotEmpty && _numPedidoHasta.isNotEmpty) {
        int numP = int.tryParse(p.numeroPedido.replaceAll(RegExp(r'\D'), '')) ?? 0;
        int d = int.tryParse(_numPedidoDesde) ?? 0;
        int h = int.tryParse(_numPedidoHasta) ?? 0;
        coincideRangoNum = numP >= d && numP <= h;
      }

      return coincideFecha && coincideRangoNum;
    }).toList();
  }

  Future<void> _generarYGuardarPdf() async {
    List<Pedido> seleccionados = _filtrarPedidos();
    if (seleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay pedidos seleccionados para exportar')),
      );
      return;
    }

    await Permission.storage.request();

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Reporte de Pedidos - App Ventas ExportPdf',
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.Text(widget.formatoFecha.format(DateTime.now())),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          ...seleccionados.map((p) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 15),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('${p.numeroPedido} - Cliente: ${p.cliente.nombre}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  pw.Text('Fecha: ${widget.formatoFecha.format(p.fechaCreacion)}'),
                  pw.Divider(),
                  ...p.productos.map((item) => pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('${item.cantidad}x ${item.producto.nombre}'),
                          pw.Text(widget.formatoLempiras.format(item.subtotal)),
                        ],
                      )),
                  pw.Divider(),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text('Total: ${widget.formatoLempiras.format(p.total)}',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );

    try {
      Directory? downloadsDirectory = await getExternalStorageDirectory();
      String pathBase = downloadsDirectory?.path ?? '/storage/emulated/0/Download';
      Directory folder = Directory('$pathBase/Pdf App Ventas Export');

      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      String nombreArchivo = 'Reporte_${DateTime.now().millisecondsSinceEpoch}.pdf';
      File file = File('${folder.path}/$nombreArchivo');
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF guardado en: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar PDF: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          const Text('Filtro de Exportación a PDF', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Pedido Desde (#)', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  onChanged: (val) => setState(() => _numPedidoDesde = val),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Pedido Hasta (#)', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  onChanged: (val) => setState(() => _numPedidoHasta = val),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Exportar a PDF (Tamaño Carta)'),
            onPressed: _generarYGuardarPdf,
          ),
          const Divider(height: 30),
          Expanded(
            child: ListView(
              children: _filtrarPedidos()
                  .map((p) => ListTile(
                        title: Text('${p.numeroPedido} - ${p.cliente.nombre}'),
                        subtitle: Text(widget.formatoLempiras.format(p.total)),
                      ))
                  .toList(),
            ),
          )
        ],
      ),
    );
  }
}