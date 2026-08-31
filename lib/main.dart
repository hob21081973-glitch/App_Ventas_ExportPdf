import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

// === ENLACES PUBLICADOS EN CSV DE GOOGLE SHEETS ===
const String urlClientesCSV = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vQGrudWaUvLeoYiWVqTA_yUMfVnCHdSSrI-NxScUAGmJhXtasntJiGz4QAZnK2ioKgPFqP6NoGcyUjs/pub?gid=0&single=true&output=csv';
const String urlProductosCSV = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vQGrudWaUvLeoYiWVqTA_yUMfVnCHdSSrI-NxScUAGmJhXtasntJiGz4QAZnK2ioKgPFqP6NoGcyUjs/pub?gid=2053635523&single=true&output=csv';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.instance.database;
  runApp(const MiApp());
}

// --- BASE DE DATOS LOCAL SQLITE ---
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('Base_De_Datos_App_Ventas.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE clientes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        telefono TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE productos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        precio REAL NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE pedidos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cliente TEXT NOT NULL,
        telefono TEXT NOT NULL,
        total REAL NOT NULL,
        detalle TEXT NOT NULL,
        fecha TEXT NOT NULL
      )
    ''');
  }

  Future<void> reiniciarPedidos() async {
    final db = await instance.database;
    await db.delete('pedidos');
  }
}

// --- MODELOS ---
class Cliente {
  final int? id;
  final String nombre;
  final String telefono;
  Cliente({this.id, required this.nombre, required this.telefono});

  Map<String, dynamic> toMap() => {'id': id, 'nombre': nombre, 'telefono': telefono};
  factory Cliente.fromMap(Map<String, dynamic> map) => Cliente(
    id: map['id'],
    nombre: map['nombre'],
    telefono: map['telefono'],
  );
}

class Producto {
  final int? id;
  final String nombre;
  final double precio;
  Producto({this.id, required this.nombre, required this.precio});

  Map<String, dynamic> toMap() => {'id': id, 'nombre': nombre, 'precio': precio};
  factory Producto.fromMap(Map<String, dynamic> map) => Producto(
    id: map['id'],
    nombre: map['nombre'],
    precio: map['precio'],
  );
}

class Pedido {
  final int? id;
  final String cliente;
  final String telefono;
  final double total;
  final String detalle;
  final String fecha;

  Pedido({this.id, required this.cliente, required this.telefono, required this.total, required this.detalle, required this.fecha});

  Map<String, dynamic> toMap() => {
    'id': id,
    'cliente': cliente,
    'telefono': telefono,
    'total': total,
    'detalle': detalle,
    'fecha': fecha,
  };

  factory Pedido.fromMap(Map<String, dynamic> map) => Pedido(
    id: map['id'],
    cliente: map['cliente'],
    telefono: map['telefono'],
    total: map['total'],
    detalle: map['detalle'],
    fecha: map['fecha'],
  );
}

// --- APLICACIÓN PRINCIPAL ---
class MiApp extends StatelessWidget {
  const MiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Ventas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.indigo, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      home: const PantallaPrincipal(),
    );
  }
}

class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({super.key});

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sistema de Pedidos', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.amberAccent,
            indicatorWeight: 3,
            tabs: [
              Tab(text: 'Nuevo Pedido'),
              Tab(text: 'Historial'),
              Tab(text: 'Clientes'),
              Tab(text: 'Productos'),
              Tab(text: 'Resumen'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            VistaNuevoPedido(),
            VistaHistorial(),
            VistaGestionClientes(),
            VistaGestionProductos(),
            VistaResumenes(),
          ],
        ),
      ),
    );
  }
}

// --- PESTAÑA 1: NUEVO PEDIDO ---
class VistaNuevoPedido extends StatefulWidget {
  const VistaNuevoPedido({super.key});

  @override
  State<VistaNuevoPedido> createState() => _VistaNuevoPedidoState();
}

class _VistaNuevoPedidoState extends State<VistaNuevoPedido> with AutomaticKeepAliveClientMixin {
  Cliente? clienteSeleccionado;
  Map<Producto, int> carrito = {};

  @override
  bool get wantKeepAlive => true;

  double get totalPedido => carrito.entries.fold(0, (sum, entry) => sum + (entry.key.precio * entry.value));

  void _abrirBuscadorCliente() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> res = await db.query('clientes');
    List<Cliente> clientes = res.map((c) => Cliente.fromMap(c)).toList();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        String filtro = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtrados = clientes.where((c) => c.nombre.toLowerCase().contains(filtro.toLowerCase())).toList();
            return Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.85,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Buscar Cliente',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (val) => setModalState(() => filtro = val),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filtrados.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) => ListTile(
                        title: Text(filtrados[i].nombre, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        subtitle: Text(filtrados[i].telefono, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        onTap: () {
                          setState(() => clienteSeleccionado = filtrados[i]);
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _abrirCatalogoProductos() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> res = await db.query('productos');
    List<Producto> productos = res.map((p) => Producto.fromMap(p)).toList();

    if (!mounted) return;

    // Cambiado a BottomSheet para ocupar todo el ancho de la pantalla igual que Clientes
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        String filtro = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtrados = productos.where((p) => p.nombre.toLowerCase().contains(filtro.toLowerCase())).toList();
            return Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.85,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Catálogo de Productos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Buscar Producto',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (val) => setModalState(() => filtro = val),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filtrados.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final prod = filtrados[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          title: Text(prod.nombre, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          subtitle: Text('L ${prod.precio.toStringAsFixed(2)} c/u', style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                          trailing: const Icon(Icons.add_circle, color: Colors.indigo, size: 28),
                          onTap: () {
                            setState(() {
                              int actual = carrito[prod] ?? 0;
                              carrito[prod] = actual + 1;
                            });
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _guardarPedido() async {
    if (clienteSeleccionado == null || carrito.isEmpty) return;

    String detalleText = '';
    carrito.forEach((prod, cant) {
      detalleText += '• ${cant}x ${prod.nombre} (L ${(prod.precio * cant).toStringAsFixed(2)})\n';
    });

    final db = await DatabaseHelper.instance.database;
    final nuevoPedido = Pedido(
      cliente: clienteSeleccionado!.nombre,
      telefono: clienteSeleccionado!.telefono,
      total: totalPedido,
      detalle: detalleText,
      fecha: DateTime.now().toString().substring(0, 10),
    );

    await db.insert('pedidos', nuevoPedido.toMap());

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('¡Pedido guardado correctamente en el Historial!')),
    );

    setState(() {
      carrito.clear();
      clienteSeleccionado = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.person_search, color: Colors.indigo),
              label: Text(
                clienteSeleccionado == null ? 'Seleccionar Cliente' : 'Cliente: ${clienteSeleccionado!.nombre}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo),
              ),
              onPressed: _abrirBuscadorCliente,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
              icon: const Icon(Icons.add_shopping_cart, color: Colors.white),
              label: const Text('+ Agregar Productos al Pedido', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: _abrirCatalogoProductos,
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: carrito.isEmpty
                ? const Center(child: Text('Ningún producto agregado aún.', style: TextStyle(color: Colors.grey)))
                : ListView(
                    children: carrito.entries.map((entry) {
                      final prod = entry.key;
                      final cant = entry.value;
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(prod.nombre, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text('L ${prod.precio.toStringAsFixed(2)} c/u | Subtotal: L ${(prod.precio * cant).toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: Colors.black87)),
                                  ],
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(4),
                                    icon: const Icon(Icons.remove_circle_outline, size: 24, color: Colors.red),
                                    onPressed: () {
                                      setState(() {
                                        if (cant == 1) {
                                          carrito.remove(prod);
                                        } else {
                                          carrito[prod] = cant - 1;
                                        }
                                      });
                                    },
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: Text('$cant', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  ),
                                  IconButton(
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(4),
                                    icon: const Icon(Icons.add_circle_outline, size: 24, color: Colors.green),
                                    onPressed: () {
                                      setState(() {
                                        carrito[prod] = cant + 1;
                                      });
                                    },
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('TOTAL:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text('L ${totalPedido.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green.shade900)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: (clienteSeleccionado != null && carrito.isNotEmpty) ? Colors.green.shade700 : Colors.grey.shade400,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: (clienteSeleccionado != null && carrito.isNotEmpty) ? _guardarPedido : null,
              child: const Text('Guardar Pedido', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          )
        ],
      ),
    );
  }
}

// --- PESTAÑA 2: HISTORIAL DE PEDIDOS ---
class VistaHistorial extends StatefulWidget {
  const VistaHistorial({super.key});

  @override
  State<VistaHistorial> createState() => _VistaHistorialState();
}

class _VistaHistorialState extends State<VistaHistorial> {

  void _confirmarEliminarPedido(Pedido pedido) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Pedido'),
        content: Text('¿Deseas eliminar definitivamente el Pedido #${pedido.id} de "${pedido.cliente}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final db = await DatabaseHelper.instance.database;
              await db.delete('pedidos', where: 'id = ?', whereArgs: [pedido.id]);
              if (mounted) Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _abrirEditarPedidoModal(Pedido pedido) async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> res = await db.query('productos');
    List<Producto> productosBD = res.map((p) => Producto.fromMap(p)).toList();

    Map<Producto, int> carritoEditado = {};
    List<String> lineas = pedido.detalle.split('\n');

    for (var linea in lineas) {
      if (linea.startsWith('• ')) {
        try {
          int indexX = linea.indexOf('x ');
          int indexPar = linea.lastIndexOf(' (L ');
          if (indexX != -1 && indexPar != -1) {
            int cant = int.parse(linea.substring(2, indexX));
            String nombreProd = linea.substring(indexX + 2, indexPar);

            Producto? p = productosBD.firstWhere(
              (element) => element.nombre == nombreProd,
              orElse: () => Producto(nombre: nombreProd, precio: 0.0),
            );
            carritoEditado[p] = cant;
          }
        } catch (_) {}
      }
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        String filtro = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double nuevoTotal = carritoEditado.entries.fold(0, (sum, entry) => sum + (entry.key.precio * entry.value));
            final filtrados = productosBD.where((p) => p.nombre.toLowerCase().contains(filtro.toLowerCase())).toList();

            return Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.85,
              child: Column(
                children: [
                  Text('Modificar Pedido #${pedido.id}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(labelText: 'Buscar producto...', prefixIcon: Icon(Icons.search)),
                    onChanged: (val) => setDialogState(() => filtro = val),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtrados.length,
                      itemBuilder: (ctx, i) {
                        final prod = filtrados[i];
                        final cant = carritoEditado[prod] ?? 0;
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black12))),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(prod.nombre, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                                    Text('L ${prod.precio.toStringAsFixed(2)} c/u', style: const TextStyle(fontSize: 11)),
                                  ],
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(4),
                                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                                    onPressed: cant > 0
                                        ? () {
                                            setDialogState(() {
                                              if (cant == 1) {
                                                carritoEditado.remove(prod);
                                              } else {
                                                carritoEditado[prod] = cant - 1;
                                              }
                                            });
                                          }
                                        : null,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Text('$cant', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  ),
                                  IconButton(
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(4),
                                    icon: const Icon(Icons.add_circle_outline, size: 20),
                                    onPressed: () {
                                      setDialogState(() {
                                        carritoEditado[prod] = cant + 1;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Nuevo Total: L ${nuevoTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                      ),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                          onPressed: () async {
                            String nuevoDetalle = '';
                            carritoEditado.forEach((prod, cant) {
                              nuevoDetalle += '• ${cant}x ${prod.nombre} (L ${(prod.precio * cant).toStringAsFixed(2)})\n';
                            });

                            final dbUpdate = await DatabaseHelper.instance.database;
                            await dbUpdate.update(
                              'pedidos',
                              {
                                'total': nuevoTotal,
                                'detalle': nuevoDetalle,
                              },
                              where: 'id = ?',
                              whereArgs: [pedido.id],
                            );

                            if (mounted) Navigator.pop(ctx);
                            setState(() {});
                          },
                          child: const Text('Guardar Cambios', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper.instance.database.then((db) => db.query('pedidos', orderBy: 'id DESC')),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final pedidos = snapshot.data!.map((p) => Pedido.fromMap(p)).toList();

        if (pedidos.isEmpty) return const Center(child: Text('No hay pedidos registrados en el historial.', style: TextStyle(color: Colors.grey)));

        return ListView.builder(
          itemCount: pedidos.length,
          itemBuilder: (ctx, i) {
            final ped = pedidos[i];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: ExpansionTile(
                title: Text('Pedido #${ped.id} - ${ped.cliente}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                subtitle: Text('Total: L ${ped.total.toStringAsFixed(2)} | Fecha: ${ped.fecha}', style: const TextStyle(fontSize: 12, color: Colors.indigo)),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Teléfono: ${ped.telefono}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 6),
                        const Text('Detalle:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        Text(ped.detalle, style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
                              icon: const Icon(Icons.edit, size: 16, color: Colors.white),
                              label: const Text('Editar', style: TextStyle(fontSize: 12, color: Colors.white)),
                              onPressed: () => _abrirEditarPedidoModal(ped),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
                              icon: const Icon(Icons.send, size: 16, color: Colors.white),
                              label: const Text('WhatsApp', style: TextStyle(fontSize: 12, color: Colors.white)),
                              onPressed: () async {
                                String mensaje = '¡Hola ${ped.cliente}!\n\nRecordatorio de tu pedido:\n${ped.detalle}\nTotal: L ${ped.total.toStringAsFixed(2)}';
                                final url = Uri.parse('https://wa.me/${ped.telefono}?text=${Uri.encodeComponent(mensaje)}');
                                if (await canLaunchUrl(url)) await launchUrl(url);
                              },
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                              icon: const Icon(Icons.delete_outline, size: 16, color: Colors.white),
                              label: const Text('Eliminar', style: TextStyle(fontSize: 12, color: Colors.white)),
                              onPressed: () => _confirmarEliminarPedido(ped),
                            ),
                          ],
                        )
                      ],
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// --- PESTAÑA 3: GESTIÓN DE CLIENTES ---
class VistaGestionClientes extends StatefulWidget {
  const VistaGestionClientes({super.key});

  @override
  State<VistaGestionClientes> createState() => _VistaGestionClientesState();
}

class _VistaGestionClientesState extends State<VistaGestionClientes> {
  final _nombreCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  String _busqueda = '';
  bool _cargando = false;

  Future<void> _sincronizarClientes() async {
    setState(() => _cargando = true);
    try {
      final res = await http.get(Uri.parse(urlClientesCSV));
      if (res.statusCode == 200) {
        final lineas = res.body.split('\n');
        final db = await DatabaseHelper.instance.database;
        int contador = 0;

        for (int i = 1; i < lineas.length; i++) {
          final campos = lineas[i].split(',');
          if (campos.length >= 2) {
            final nombre = campos[0].trim().replaceAll('"', '');
            final telefono = campos[1].trim().replaceAll('"', '');

            if (nombre.isNotEmpty) {
              await db.insert('clientes', {'nombre': nombre, 'telefono': telefono});
              contador++;
            }
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('¡$contador clientes importados con éxito!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al importar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _guardarOActualizarCliente({Cliente? clienteExistente}) async {
    final nombre = _nombreCtrl.text.trim();
    final telefono = _telCtrl.text.trim();

    if (nombre.isEmpty || telefono.isEmpty) return;

    final db = await DatabaseHelper.instance.database;

    if (clienteExistente == null) {
      await db.insert('clientes', {'nombre': nombre, 'telefono': telefono});
    } else {
      await db.update(
        'clientes',
        {'nombre': nombre, 'telefono': telefono},
        where: 'id = ?',
        whereArgs: [clienteExistente.id],
      );
    }

    _nombreCtrl.clear();
    _telCtrl.clear();
    if (mounted) Navigator.pop(context);
    setState(() {});
  }

  void _confirmarEliminarCliente(Cliente cliente) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Cliente'),
        content: Text('¿Estás seguro de que deseas eliminar a "${cliente.nombre}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final db = await DatabaseHelper.instance.database;
              await db.delete('clientes', where: 'id = ?', whereArgs: [cliente.id]);
              if (mounted) Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  void _abrirFormularioModal({Cliente? cliente}) {
    if (cliente != null) {
      _nombreCtrl.text = cliente.nombre;
      _telCtrl.text = cliente.telefono;
    } else {
      _nombreCtrl.clear();
      _telCtrl.clear();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          top: 16,
          left: 16,
          right: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              cliente == null ? 'Agregar Nuevo Cliente' : 'Editar Cliente',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nombreCtrl,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            TextField(
              controller: _telCtrl,
              decoration: const InputDecoration(labelText: 'Teléfono'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
              icon: const Icon(Icons.save, color: Colors.white),
              label: Text(cliente == null ? 'Guardar Cliente' : 'Actualizar Cliente', style: const TextStyle(color: Colors.white)),
              onPressed: () => _guardarOActualizarCliente(clienteExistente: cliente),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.indigo,
        onPressed: () => _abrirFormularioModal(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'Buscar cliente...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (val) => setState(() => _busqueda = val),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Cargar desde Excel/Google Sheets',
                  icon: _cargando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_download, color: Colors.indigo, size: 28),
                  onPressed: _cargando ? null : _sincronizarClientes,
                )
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: DatabaseHelper.instance.database.then((db) => db.query('clientes')),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final lista = snapshot.data!
                    .map((c) => Cliente.fromMap(c))
                    .where((c) => c.nombre.toLowerCase().contains(_busqueda.toLowerCase()) ||
                                  c.telefono.contains(_busqueda))
                    .toList();

                if (lista.isEmpty) return const Center(child: Text('No hay clientes registrados.', style: TextStyle(color: Colors.grey)));

                return ListView.separated(
                  itemCount: lista.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final item = lista[i];
                    return ListTile(
                      title: Text(item.nombre, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: Text(item.telefono, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.indigo, size: 22),
                            onPressed: () => _abrirFormularioModal(cliente: item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red, size: 22),
                            onPressed: () => _confirmarEliminarCliente(item),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- PESTAÑA 4: GESTIÓN DE PRODUCTOS ---
class VistaGestionProductos extends StatefulWidget {
  const VistaGestionProductos({super.key});

  @override
  State<VistaGestionProductos> createState() => _VistaGestionProductosState();
}

class _VistaGestionProductosState extends State<VistaGestionProductos> {
  final _nombreCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  String _busqueda = '';
  bool _cargando = false;

  Future<void> _sincronizarProductos() async {
    setState(() => _cargando = true);
    try {
      final res = await http.get(Uri.parse(urlProductosCSV));
      if (res.statusCode == 200) {
        final lineas = res.body.split('\n');
        final db = await DatabaseHelper.instance.database;
        int contador = 0;

        for (int i = 1; i < lineas.length; i++) {
          final campos = lineas[i].split(',');
          if (campos.length >= 2) {
            final nombre = campos[0].trim().replaceAll('"', '');
            final precioText = campos[1].trim().replaceAll('"', '');
            final precio = double.tryParse(precioText) ?? 0.0;

            if (nombre.isNotEmpty && precio > 0) {
              await db.insert('productos', {'nombre': nombre, 'precio': precio});
              contador++;
            }
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('¡$contador productos importados con éxito!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al importar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _guardarOActualizarProducto({Producto? productoExistente}) async {
    final nombre = _nombreCtrl.text.trim();
    final precio = double.tryParse(_precioCtrl.text) ?? 0.0;

    if (nombre.isEmpty || precio <= 0) return;

    final db = await DatabaseHelper.instance.database;

    if (productoExistente == null) {
      await db.insert('productos', {'nombre': nombre, 'precio': precio});
    } else {
      await db.update(
        'productos',
        {'nombre': nombre, 'precio': precio},
        where: 'id = ?',
        whereArgs: [productoExistente.id],
      );
    }

    _nombreCtrl.clear();
    _precioCtrl.clear();
    if (mounted) Navigator.pop(context);
    setState(() {});
  }

  void _confirmarEliminarProducto(Producto producto) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Producto'),
        content: Text('¿Estás seguro de que deseas eliminar "${producto.nombre}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final db = await DatabaseHelper.instance.database;
              await db.delete('productos', where: 'id = ?', whereArgs: [producto.id]);
              if (mounted) Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  void _abrirFormularioModal({Producto? producto}) {
    if (producto != null) {
      _nombreCtrl.text = producto.nombre;
      _precioCtrl.text = producto.precio.toString();
    } else {
      _nombreCtrl.clear();
      _precioCtrl.clear();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          top: 16,
          left: 16,
          right: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              producto == null ? 'Agregar Nuevo Producto' : 'Editar Producto',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nombreCtrl,
              decoration: const InputDecoration(labelText: 'Producto'),
            ),
            TextField(
              controller: _precioCtrl,
              decoration: const InputDecoration(labelText: 'Precio (L)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
              icon: const Icon(Icons.save, color: Colors.white),
              label: Text(producto == null ? 'Guardar Producto' : 'Actualizar Producto', style: const TextStyle(color: Colors.white)),
              onPressed: () => _guardarOActualizarProducto(productoExistente: producto),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.indigo,
        onPressed: () => _abrirFormularioModal(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'Buscar producto...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (val) => setState(() => _busqueda = val),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Cargar desde Excel/Google Sheets',
                  icon: _cargando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_download, color: Colors.indigo, size: 28),
                  onPressed: _cargando ? null : _sincronizarProductos,
                )
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: DatabaseHelper.instance.database.then((db) => db.query('productos')),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final lista = snapshot.data!
                    .map((p) => Producto.fromMap(p))
                    .where((p) => p.nombre.toLowerCase().contains(_busqueda.toLowerCase()))
                    .toList();

                if (lista.isEmpty) return const Center(child: Text('No hay productos registrados.', style: TextStyle(color: Colors.grey)));

                return ListView.separated(
                  itemCount: lista.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final item = lista[i];
                    return ListTile(
                      title: Text(item.nombre, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: Text('L ${item.precio.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: Colors.green)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.indigo, size: 22),
                            onPressed: () => _abrirFormularioModal(producto: item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red, size: 22),
                            onPressed: () => _confirmarEliminarProducto(item),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- PESTAÑA 5: RESUMEN DE VENTAS ---
class VistaResumenes extends StatefulWidget {
  const VistaResumenes({super.key});

  @override
  State<VistaResumenes> createState() => _VistaResumenesState();
}

class _VistaResumenesState extends State<VistaResumenes> {

  void _confirmarReiniciarSemana() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reiniciar Conteo Semanal'),
        content: const Text('¿Estás seguro de que deseas borrar todos los pedidos del historial para iniciar una nueva semana?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await DatabaseHelper.instance.reiniciarPedidos();
              if (mounted) Navigator.pop(ctx);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('¡Historial de pedidos reiniciado a 0!')),
              );
            },
            child: const Text('Sí, Reiniciar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper.instance.database.then((db) => db.query('pedidos')),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final pedidos = snapshot.data!.map((p) => Pedido.fromMap(p)).toList();

        double totalVentas = pedidos.fold(0, (sum, p) => sum + p.total);
        Map<String, double> ventasPorCliente = {};

        for (var p in pedidos) {
          ventasPorCliente[p.cliente] = (ventasPorCliente[p.cliente] ?? 0) + p.total;
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                color: Colors.green.shade100,
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  title: const Text('Ventas Totales Registradas', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('L ${totalVentas.toStringAsFixed(2)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                  trailing: const Icon(Icons.monetization_on, color: Colors.green, size: 36),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.restart_alt, color: Colors.white),
                  label: const Text('Reiniciar Pedidos de la Semana', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  onPressed: _confirmarReiniciarSemana,
                ),
              ),
              const SizedBox(height: 16),
              const Text('Resumen de Ventas por Cliente:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Divider(height: 16),
              Expanded(
                child: ventasPorCliente.isEmpty
                    ? const Center(child: Text('No hay ventas en la semana actual.', style: TextStyle(color: Colors.grey)))
                    : ListView(
                        children: ventasPorCliente.entries.map((e) {
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Colors.indigo,
                                child: Icon(Icons.person, color: Colors.white, size: 20),
                              ),
                              title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              trailing: Text('L ${e.value.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14)),
                            ),
                          );
                        }).toList(),
                      ),
              )
            ],
          ),
        );
      },
    );
  }
}
