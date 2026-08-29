import 'dart:convert';
import 'package:http/http.dart' as http;

class Cliente {
  String codigo;
  String nombre;
  String telefono;
  String direccion;

  Cliente({
    required this.codigo,
    required this.nombre,
    required this.telefono,
    required this.direccion,
  });

  factory Cliente.fromJson(List<dynamic> json) {
    return Cliente(
      codigo: json[0].toString(),
      nombre: json[1].toString(),
      telefono: json.length > 2 ? json[2].toString() : '',
      direccion: json.length > 3 ? json[3].toString() : '',
    );
  }
}

class Producto {
  String codigo;
  String nombre;
  double precio;
  int stock;

  Producto({
    required this.codigo,
    required this.nombre,
    required this.precio,
    required this.stock,
  });

  factory Producto.fromJson(List<dynamic> json) {
    return Producto(
      codigo: json[0].toString(),
      nombre: json[1].toString(),
      precio: double.tryParse(json[2].toString()) ?? 0.0,
      stock: int.tryParse(json[3].toString()) ?? 0,
    );
  }
}

class GoogleSheetsService {
  // Pega aquí la URL de tu Web App de Google Apps Script
  static const String webAppUrl = 'https://script.google.com/macros/s/AKfycbyiT2h9i6JyJvfHHk72xEtCEzHNdst5uHtMKfRJH_oXqZqloqiiX-jFmY3fA96JuoY9/exec';

  // --- OBTENER DATOS ---
  static Future<List<Cliente>> obtenerClientes() async {
    try {
      final res = await http.get(Uri.parse('$webAppUrl?action=getClientes'));
      if (res.statusCode == 200) {
        List<dynamic> data = jsonDecode(res.body);
        return data.where((r) => r.isNotEmpty && r[0].toString().isNotEmpty).map((item) => Cliente.fromJson(item)).toList();
      }
    } catch (e) {
      print('Error clientes: $e');
    }
    return [];
  }

  static Future<List<Producto>> obtenerProductos() async {
    try {
      final res = await http.get(Uri.parse('$webAppUrl?action=getProductos'));
      if (res.statusCode == 200) {
        List<dynamic> data = jsonDecode(res.body);
        return data.where((r) => r.isNotEmpty && r[0].toString().isNotEmpty).map((item) => Producto.fromJson(item)).toList();
      }
    } catch (e) {
      print('Error productos: $e');
    }
    return [];
  }

  // --- EDITAR CLIENTE ---
  static Future<bool> editarCliente(Cliente c) async {
    final res = await http.post(
      Uri.parse(webAppUrl),
      body: jsonEncode({
        'action': 'editarCliente',
        'codigo': c.codigo,
        'nombre': c.nombre,
        'telefono': c.telefono,
        'direccion': c.direccion,
      }),
    );
    return res.statusCode == 200;
  }

  // --- ELIMINAR CLIENTE ---
  static Future<bool> eliminarCliente(String codigo) async {
    final res = await http.post(
      Uri.parse(webAppUrl),
      body: jsonEncode({'action': 'eliminarCliente', 'codigo': codigo}),
    );
    return res.statusCode == 200;
  }

  // --- EDITAR PRODUCTO ---
  static Future<bool> editarProducto(Producto p) async {
    final res = await http.post(
      Uri.parse(webAppUrl),
      body: jsonEncode({
        'action': 'editarProducto',
        'codigo': p.codigo,
        'nombre': p.nombre,
        'precio': p.precio,
        'stock': p.stock,
      }),
    );
    return res.statusCode == 200;
  }

  // --- ELIMINAR PRODUCTO ---
  static Future<bool> eliminarProducto(String codigo) async {
    final res = await http.post(
      Uri.parse(webAppUrl),
      body: jsonEncode({'action': 'eliminarProducto', 'codigo': codigo}),
    );
    return res.statusCode == 200;
  }
}