import 'package:flutter/material.dart';
import 'google_sheets_service.dart';

void main() {
  runApp(const MiAppVentas());
}

class MiAppVentas extends StatelessWidget {
  const MiAppVentas({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'App Ventas ExportPdf',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: false,
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
  int _indicePestana = 2; // Iniciar en Clientes por defecto
  List<Cliente> clientes = [];
  List<Producto> productos = [];
  bool cargando = false;

  @override
  void initState() {
    super.initState();
    cargarDatosDesdeSheets();
  }

  Future<void> cargarDatosDesdeSheets() async {
    setState(() => cargando = true);
    final listaClientes = await GoogleSheetsService.obtenerClientes();
    final listaProductos = await GoogleSheetsService.obtenerProductos();

    setState(() {
      clientes = listaClientes;
      productos = listaProductos;
      cargando = false;
    });
  }

  // --- DIÁLOGOS DE EDICIÓN Y ELIMINACIÓN: CLIENTES ---
  void _mostrarDialogoEditarCliente(Cliente c) {
    final txtNombre = TextEditingController(text: c.nombre);
    final txtTelefono = TextEditingController(text: c.telefono);
    final txtDireccion = TextEditingController(text: c.direccion);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar Cliente (${c.codigo})'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: txtNombre, decoration: const InputDecoration(labelText: 'Nombre')),
              TextField(controller: txtTelefono, decoration: const InputDecoration(labelText: 'Teléfono')),
              TextField(controller: txtDireccion, decoration: const InputDecoration(labelText: 'Dirección')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              c.nombre = txtNombre.text;
              c.telefono = txtTelefono.text;
              c.direccion = txtDireccion.text;
              setState(() => cargando = true);
              await GoogleSheetsService.editarCliente(c);
              await cargarDatosDesdeSheets();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _confirmarEliminarCliente(Cliente c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Cliente'),
        content: Text('¿Deseas eliminar a ${c.nombre}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => cargando = true);
              await GoogleSheetsService.eliminarCliente(c.codigo);
              await cargarDatosDesdeSheets();
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  // --- DIÁLOGOS DE EDICIÓN Y ELIMINACIÓN: PRODUCTOS ---
  void _mostrarDialogoEditarProducto(Producto p) {
    final txtNombre = TextEditingController(text: p.nombre);
    final txtPrecio = TextEditingController(text: p.precio.toString());
    final txtStock = TextEditingController(text: p.stock.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar Producto (${p.codigo})'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: txtNombre, decoration: const InputDecoration(labelText: 'Nombre')),
              TextField(controller: txtPrecio, decoration: const InputDecoration(labelText: 'Precio'), keyboardType: TextInputType.number),
              TextField(controller: txtStock, decoration: const InputDecoration(labelText: 'Stock'), keyboardType: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              p.nombre = txtNombre.text;
              p.precio = double.tryParse(txtPrecio.text) ?? p.precio;
              p.stock = int.tryParse(txtStock.text) ?? p.stock;
              setState(() => cargando = true);
              await GoogleSheetsService.editarProducto(p);
              await cargarDatosDesdeSheets();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _confirmarEliminarProducto(Producto p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Producto'),
        content: Text('¿Deseas eliminar el producto ${p.nombre}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => cargando = true);
              await GoogleSheetsService.eliminarProducto(p.codigo);
              await cargarDatosDesdeSheets();
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paginas = [
      const Center(child: Text('Pantalla Crear')),
      const Center(child: Text('Pantalla Historial')),
      
      // PESTAÑA CLIENTES CON BOTONES EDITAR / ELIMINAR
      cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: clientes.length,
              itemBuilder: (context, i) {
                final c = clientes[i];
                return ListTile(
                  leading: CircleAvatar(child: Text(c.codigo)),
                  title: Text(c.nombre),
                  subtitle: Text('Teléfono: ${c.telefono}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _mostrarDialogoEditarCliente(c),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmarEliminarCliente(c),
                      ),
                    ],
                  ),
                );
              },
            ),

      // PESTAÑA PRODUCTOS CON BOTONES EDITAR / ELIMINAR
      cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: productos.length,
              itemBuilder: (context, i) {
                final p = productos[i];
                return ListTile(
                  leading: CircleAvatar(child: Text(p.codigo)),
                  title: Text(p.nombre),
                  subtitle: Text('L ${p.precio.toStringAsFixed(2)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _mostrarDialogoEditarProducto(p),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmarEliminarProducto(p),
                      ),
                    ],
                  ),
                );
              },
            ),

      const Center(child: Text('Pantalla Resumen')),
      const Center(child: Text('Pantalla Productos Barcode')),
      const Center(child: Text('Pantalla PDF')),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Ventas ExportPdf'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: cargarDatosDesdeSheets,
          )
        ],
      ),
      body: paginas[_indicePestana],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _indicePestana,
        onTap: (index) => setState(() => _indicePestana = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: 'Crear'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Historial'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Clientes'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'Productos'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Resumen'),
          BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Prod...'),
          BottomNavigationBarItem(icon: Icon(Icons.picture_as_pdf), label: 'PDF'),
        ],
      ),
    );
  }
}