import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

// URLs de Google Sheets (Reemplaza con tus enlaces CSV publicados)
const String urlClientesCSV = 'https://docs.google.com/spreadsheets/d/TU_ID_CLIENTES/export?format=csv';
const String urlProductosCSV = 'https://docs.google.com/spreadsheets/d/TU_ID_PRODUCTOS/export?format=csv';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppVentasExportPdf());
}

class AppVentasExportPdf extends StatelessWidget {
  const AppVentasExportPdf({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Ventas ExportPdf',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const MenuPrincipal(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ==========================================
// BASE DE DATOS LOCAL (SQLITE)
// ==========================================
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('ventas_app.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = '${dbPath}/$filePath'; // Manejo directo de ruta sin importar conflictive path package

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE clientes (
        codigo TEXT PRIMARY KEY,
        nombre TEXT,
        telefono TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE productos (
        codigo TEXT PRIMARY KEY,
        nombre TEXT,
        precio REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE pedidos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        numero_pedido TEXT,
        cliente TEXT,
        productos_json TEXT,
        total REAL,
        fecha TEXT
      )
    ''');
  }

  Future<void> sincronizarClientesDesdeCSV(String csvData) async {
    final db = await instance.database;
    List<String> lineas = csvData.split('\n');
    await db.transaction((txn) async {
      await txn.delete('clientes');
      for (int i = 1; i < lineas.length; i++) {
        var linea = lineas[i].trim();
        if (linea.isEmpty) continue;
        List<String> cols = linea.split(',');
        if (cols.length >= 3) {
          await txn.insert('clientes', {
            'codigo': cols[0].replaceAll('"', '').trim(),
            'nombre': cols[1].replaceAll('"', '').trim(),
            'telefono': cols[2].replaceAll('"', '').trim(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  Future<void> sincronizarProductosDesdeCSV(String csvData) async {
    final db = await instance.database;
    List<String> lineas = csvData.split('\n');
    await db.transaction((txn) async {
      await txn.delete('productos');
      for (int i = 1; i < lineas.length; i++) {
        var linea = lineas[i].trim();
        if (linea.isEmpty) continue;
        List<String> cols = linea.split(',');
        if (cols.length >= 3) {
          String precioStr = cols[2].replaceAll('L', '').replaceAll(',', '').replaceAll('"', '').trim();
          double precio = double.tryParse(precioStr) ?? 0.0;
          await txn.insert('productos', {
            'codigo': cols[0].replaceAll('"', '').trim(),
            'nombre': cols[1].replaceAll('"', '').trim(),
            'precio': precio,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }
}

// ==========================================
// MENÚ PRINCIPAL CON PESTAÑAS
// ==========================================
class MenuPrincipal extends StatefulWidget {
  const MenuPrincipal({super.key});

  @override
  State<MenuPrincipal> createState() => _MenuPrincipalState();
}

class _MenuPrincipalState extends State<MenuPrincipal> {
  int _indiceActual = 0;

  final List<Widget> _pantallas = [
    const VistaCrearPedido(),
    const VistaHistorialPedidos(),
    const VistaGestionClientes(),
    const VistaGestionProductos(),
    const VistaResumenGeneral(),
    const VistaResumenProductos(),
    const VistaExportarPdf(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Ventas ExportPdf'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _pantallas[_indiceActual],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _indiceActual,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.indigo,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _indiceActual = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.add_shopping_cart), label: 'Crear'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Historial'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Clientes'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: 'Productos'),
          BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Resumen'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Por Prod.'),
          BottomNavigationBarItem(icon: Icon(Icons.picture_as_pdf), label: 'Exportar'),
        ],
      ),
    );
  }
}

// ==========================================
// 1. PESTAÑA: CREAR PEDIDO
// ==========================================
class VistaCrearPedido extends StatefulWidget {
  const VistaCrearPedido({super.key});

  @override
  State<VistaCrearPedido> createState() => _VistaCrearPedidoState();
}

class _VistaCrearPedidoState extends State<VistaCrearPedido> {
  String? clienteSeleccionado;
  List<Map<String, dynamic>> productosSeleccionados = [];
  
  final TextEditingController _searchClienteCtrl = TextEditingController();
  final TextEditingController _searchProdCtrl = TextEditingController();

  Future<int> _obtenerSiguienteNumeroPedido() async {
    final db = await DatabaseHelper.instance.database;
    final resultado = await db.rawQuery('SELECT COUNT(*) as total FROM pedidos');
    int count = Sqflite.firstIntValue(resultado) ?? 0;
    return (count % 99) + 1;
  }

  void _guardarPedido() async {
    if (clienteSeleccionado == null || productosSeleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione un cliente y al menos un producto')),
      );
      return;
    }

    int numSeq = await _obtenerSiguienteNumeroPedido();
    String numPedidoStr = 'Pedido #${numSeq.toString().padLeft(2, '0')}';
    double total = productosSeleccionados.fold(0, (sum, item) => sum + (item['precio'] * item['cantidad']));
    String fecha = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    String productosStr = productosSeleccionados.map((p) => "${p['nombre']} (x${p['cantidad']})").join('; ');

    final db = await DatabaseHelper.instance.database;
    await db.insert('pedidos', {
      'numero_pedido': numPedidoStr,
      'cliente': clienteSeleccionado,
      'productos_json': productosStr,
      'total': total,
      'fecha': fecha,
    });

    setState(() {
      clienteSeleccionado = null;
      productosSeleccionados.clear();
      _searchClienteCtrl.clear();
      _searchProdCtrl.clear();
    });

    if(!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('¡$numPedidoStr Guardado con éxito!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          const Text('1. Buscar y Seleccionar Cliente', style: TextStyle(fontWeight: FontWeight.bold)),
          TextField(
            controller: _searchClienteCtrl,
            decoration: const InputDecoration(labelText: 'Filtrar cliente...', suffixIcon: Icon(Icons.search)),
            onChanged: (val) => setState(() {}),
          ),
          SizedBox(
            height: 120,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: DatabaseHelper.instance.database.then((db) {
                String filtro = _searchClienteCtrl.text;
                return db.query('clientes', where: 'nombre LIKE ?', whereArgs: ['%$filtro%']);
              }),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final clientes = snapshot.data!;
                return ListView.builder(
                  itemCount: clientes.length,
                  itemBuilder: (context, index) {
                    final c = clientes[index];
                    return ListTile(
                      title: Text(c['nombre']),
                      subtitle: Text('Tel: ${c['telefono']}'),
                      selected: clienteSeleccionado == c['nombre'],
                      onTap: () => setState(() => clienteSeleccionado = c['nombre']),
                    );
                  },
                );
              },
            ),
          ),
          if (clienteSeleccionado != null)
            Chip(label: Text('Cliente: $clienteSeleccionado'), backgroundColor: Colors.green[100]),
          const Divider(height: 30),
          const Text('2. Buscar y Agregar Productos', style: TextStyle(fontWeight: FontWeight.bold)),
          TextField(
            controller: _searchProdCtrl,
            decoration: const InputDecoration(labelText: 'Filtrar producto...', suffixIcon: Icon(Icons.search)),
            onChanged: (val) => setState(() {}),
          ),
          SizedBox(
            height: 150,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: DatabaseHelper.instance.database.then((db) {
                String filtro = _searchProdCtrl.text;
                return db.query('productos', where: 'nombre LIKE ?', whereArgs: ['%$filtro%']);
              }),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final productos = snapshot.data!;
                return ListView.builder(
                  itemCount: productos.length,
                  itemBuilder: (context, index) {
                    final p = productos[index];
                    return ListTile(
                      title: Text(p['nombre']),
                      subtitle: Text('L ${p['precio'].toStringAsFixed(2)}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.indigo),
                        onPressed: () {
                          setState(() {
                            var existente = productosSeleccionados.firstWhere(
                              (item) => item['nombre'] == p['nombre'],
                              orElse: () => {},
                            );
                            if (existente.isNotEmpty) {
                              existente['cantidad']++;
                            } else {
                              productosSeleccionados.add({
                                'nombre': p['nombre'],
                                'precio': p['precio'],
                                'cantidad': 1,
                              });
                            }
                          });
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const Divider(),
          const Text('Productos en el Pedido Actual:', style: TextStyle(fontWeight: FontWeight.bold)),
          ...productosSeleccionados.map((item) => ListTile(
                title: Text(item['nombre']),
                subtitle: Text('Cant: ${item['cantidad']} x L ${item['precio']}'),
                trailing: Text('L ${(item['precio'] * item['cantidad']).toStringAsFixed(2)}'),
              )),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            onPressed: _guardarPedido,
            icon: const Icon(Icons.save),
            label: const Text('Guardar Pedido'),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 2. PESTAÑA: HISTORIAL DE PEDIDOS
// ==========================================
class VistaHistorialPedidos extends StatefulWidget {
  const VistaHistorialPedidos({super.key});

  @override
  State<VistaHistorialPedidos> createState() => _VistaHistorialPedidosState();
}

class _VistaHistorialPedidosState extends State<VistaHistorialPedidos> {
  Future<void> _resetearConteo() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('pedidos');
    setState(() {});
    if(!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Conteo de pedidos reseteado a 0')));
  }

  void _enviarWhatsApp(String cliente, String productos, double total) async {
    String mensaje = "Hola $cliente, tu pedido consta de: $productos. Total: L ${total.toStringAsFixed(2)}. ¡Gracias por tu compra!";
    final url = Uri.parse("https://wa.me/?text=${Uri.encodeComponent(mensaje)}");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _mostrarMenuOpciones(Map<String, dynamic> pedido) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('Editar Pedido'),
              onTap: () {
                Navigator.pop(context);
                _dialogoEditarPedido(pedido);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Eliminar Pedido'),
              onTap: () async {
                Navigator.pop(context);
                final db = await DatabaseHelper.instance.database;
                await db.delete('pedidos', where: 'id = ?', whereArgs: [pedido['id']]);
                setState(() {});
              },
            ),
          ],
        );
      },
    );
  }

  void _dialogoEditarPedido(Map<String, dynamic> pedido) {
    TextEditingController clienteCtrl = TextEditingController(text: pedido['cliente']);
    TextEditingController prodCtrl = TextEditingController(text: pedido['productos_json']);
    TextEditingController totalCtrl = TextEditingController(text: pedido['total'].toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar ${pedido['numero_pedido']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: clienteCtrl, decoration: const InputDecoration(labelText: 'Cliente')),
            TextField(controller: prodCtrl, decoration: const InputDecoration(labelText: 'Productos')),
            TextField(controller: totalCtrl, decoration: const InputDecoration(labelText: 'Total'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final db = await DatabaseHelper.instance.database;
              await db.update('pedidos', {
                'cliente': clienteCtrl.text,
                'productos_json': prodCtrl.text,
                'total': double.tryParse(totalCtrl.text) ?? 0.0,
              }, where: 'id = ?', whereArgs: [pedido['id']]);
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Resetear Conteo',
            onPressed: _resetearConteo,
          )
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseHelper.instance.database.then((db) => db.query('pedidos', orderBy: 'id DESC')),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final pedidos = snapshot.data!;
          if (pedidos.isEmpty) return const Center(child: Text('No hay pedidos registrados.'));

          return ListView.builder(
            itemCount: pedidos.length,
            itemBuilder: (context, index) {
              final p = pedidos[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  title: Text('${p['numero_pedido']} - ${p['cliente']}'),
                  subtitle: Text('${p['productos_json']}\nFecha: ${p['fecha']} | Total: L ${p['total'].toStringAsFixed(2)}'),
                  isThreeLine: true,
                  onTap: () => _mostrarMenuOpciones(p),
                  trailing: IconButton(
                    icon: const Icon(Icons.share, color: Colors.green),
                    onPressed: () => _enviarWhatsApp(p['cliente'], p['productos_json'], p['total']),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ==========================================
// 3 & 4. GESTIÓN CLIENTES Y PRODUCTOS
// ==========================================
class VistaGestionClientes extends StatefulWidget {
  const VistaGestionClientes({super.key});

  @override
  State<VistaGestionClientes> createState() => _VistaGestionClientesState();
}

class _VistaGestionClientesState extends State<VistaGestionClientes> {
  bool sincronizando = false;

  Future<void> _sincronizar() async {
    setState(() => sincronizando = true);
    try {
      final res = await http.get(Uri.parse(urlClientesCSV));
      if (res.statusCode == 200) {
        await DatabaseHelper.instance.sincronizarClientesDesdeCSV(res.body);
        if(!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clientes sincronizados')));
      }
    } catch (e) {
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => sincronizando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: sincronizando ? null : _sincronizar,
        child: const Icon(Icons.cloud_download),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseHelper.instance.database.then((db) => db.query('clientes')),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final lista = snapshot.data!;
          if(lista.isEmpty) return const Center(child: Text('Presiona el botón inferior para sincronizar Clientes.'));
          return ListView.builder(
            itemCount: lista.length,
            itemBuilder: (context, i) => ListTile(
              title: Text(lista[i]['nombre']),
              subtitle: Text('Cod: ${lista[i]['codigo']} | Tel: ${lista[i]['telefono']}'),
            ),
          );
        },
      ),
    );
  }
}

class VistaGestionProductos extends StatefulWidget {
  const VistaGestionProductos({super.key});

  @override
  State<VistaGestionProductos> createState() => _VistaGestionProductosState();
}

class _VistaGestionProductosState extends State<VistaGestionProductos> {
  bool sincronizando = false;

  Future<void> _sincronizar() async {
    setState(() => sincronizando = true);
    try {
      final res = await http.get(Uri.parse(urlProductosCSV));
      if (res.statusCode == 200) {
        await DatabaseHelper.instance.sincronizarProductosDesdeCSV(res.body);
        if(!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Productos sincronizados')));
      }
    } catch (e) {
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => sincronizando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: sincronizando ? null : _sincronizar,
        child: const Icon(Icons.cloud_download),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseHelper.instance.database.then((db) => db.query('productos')),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final lista = snapshot.data!;
          if(lista.isEmpty) return const Center(child: Text('Presiona el botón inferior para sincronizar Productos.'));
          return ListView.builder(
            itemCount: lista.length,
            itemBuilder: (context, i) => ListTile(
              title: Text(lista[i]['nombre']),
              subtitle: Text('Cod: ${lista[i]['codigo']} | Precio: L ${lista[i]['precio'].toStringAsFixed(2)}'),
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// 5. RESUMEN GENERAL
// ==========================================
class VistaResumenGeneral extends StatelessWidget {
  const VistaResumenGeneral({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper.instance.database.then((db) => db.query('pedidos')),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final pedidos = snapshot.data!;
        double totalGlobal = pedidos.fold(0, (sum, item) => sum + item['total']);
        
        Map<String, double> porFecha = {};
        Map<String, double> porCliente = {};
        
        for (var p in pedidos) {
          String fecha = p['fecha'].toString().substring(0, 10);
          String cliente = p['cliente'];
          double total = p['total'];
          porFecha[fecha] = (porFecha[fecha] ?? 0) + total;
          porCliente[cliente] = (porCliente[cliente] ?? 0) + total;
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Colors.indigo[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Venta Total General: L ${totalGlobal.toStringAsFixed(2)}', 
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const Divider(),
            const Text('Ventas por Fecha:', style: TextStyle(fontWeight: FontWeight.bold)),
            ...porFecha.entries.map((e) => ListTile(title: Text(e.key), trailing: Text('L ${e.value.toStringAsFixed(2)}'))),
            const Divider(),
            const Text('Ventas por Cliente:', style: TextStyle(fontWeight: FontWeight.bold)),
            ...porCliente.entries.map((e) => ListTile(title: Text(e.key), trailing: Text('L ${e.value.toStringAsFixed(2)}'))),
          ],
        );
      },
    );
  }
}

// ==========================================
// 6. RESUMEN POR PRODUCTO
// ==========================================
class VistaResumenProductos extends StatelessWidget {
  const VistaResumenProductos({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper.instance.database.then((db) => db.query('pedidos')),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final pedidos = snapshot.data!;
        Map<String, int> conteoUnidades = {};

        for (var p in pedidos) {
          String prodString = p['productos_json'];
          List<String> items = prodString.split(';');
          for (var item in items) {
            if(item.trim().isEmpty) continue;
            try {
              var partes = item.split('(x');
              String nombreProd = partes[0].trim();
              int cant = int.parse(partes[1].replaceAll(')', '').trim());
              conteoUnidades[nombreProd] = (conteoUnidades[nombreProd] ?? 0) + cant;
            } catch (_) {}
          }
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Resumen de Productos Vendidos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            ...conteoUnidades.entries.map((e) => ListTile(
              title: Text(e.key),
              trailing: Text('Unidades: ${e.value}'),
            )),
          ],
        );
      },
    );
  }
}

// ==========================================
// 7. EXPORTAR A PDF (Tamaño Carta)
// ==========================================
class VistaExportarPdf extends StatefulWidget {
  const VistaExportarPdf({super.key});

  @override
  State<VistaExportarPdf> createState() => _VistaExportarPdfState();
}

class _VistaExportarPdfState extends State<VistaExportarPdf> {
  String? pedidoFiltro;

  Future<void> _generarYMostrarPdf(BuildContext context) async {
    final pdf = pw.Document();
    final db = await DatabaseHelper.instance.database;
    List<Map<String, dynamic>> pedidos = await db.query('pedidos');

    if (pedidoFiltro != null && pedidoFiltro!.isNotEmpty) {
      pedidos = pedidos.where((p) => p['numero_pedido'] == pedidoFiltro).toList();
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Reporte de Ventas - App Ventas ExportPdf', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              pw.Table.fromTextArray(
                headers: ['Pedido', 'Cliente', 'Productos', 'Fecha', 'Total'],
                data: pedidos.map((p) => [
                  p['numero_pedido'],
                  p['cliente'],
                  p['productos_json'],
                  p['fecha'],
                  'L ${p['total'].toStringAsFixed(2)}',
                ]).toList(),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Exportar Pedidos a PDF (Tamaño Carta)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          TextField(
            decoration: const InputDecoration(labelText: 'Filtrar por Número de Pedido (Ej. Pedido #01)'),
            onChanged: (val) => setState(() => pedidoFiltro = val),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            onPressed: () => _generarYMostrarPdf(context),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Generar e Imprimir PDF'),
          ),
        ],
      ),
    );
  }
}
