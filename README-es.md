<!-- markdownlint-configure-file { "MD004": { "style": "consistent" } } -->
<!-- markdownlint-disable MD033 -->
#

<p align="center">
    <a href="https://pi-hole.net/">
        <img src="https://pi-hole.github.io/graphics/Vortex/Vortex_with_Wordmark.svg" width="150" height="260" alt="Pi-hole">
    </a>
    <br>
    <strong>Bloqueo de anuncios en toda la red a través de su propio hardware Linux</strong>
</p>
<!-- markdownlint-enable MD033 -->

El Pi-hole® es un [DNS sinkhole](https://en.wikipedia.org/wiki/DNS_Sinkhole) que protege sus dispositivos de contenidos no deseados, sin necesidad de instalar ningún software del lado del cliente.

- **Fácil de instalar**: nuestro versátil instalador le guía a través del proceso, y tarda menos de diez minutos
- **Resolución**: el contenido se bloquea en _situaciones no relacionadas con el navegador_, como las aplicaciones móviles cargadas de publicidad y los televisores inteligentes
- **Responsive**: acelera sin problemas la sensación de navegación diaria al almacenar en caché las consultas DNS
- Ligero**: funciona sin problemas con [requisitos mínimos de hardware y software](https://docs.pi-hole.net/main/prerequisites/)
- **Robusto**: una interfaz de línea de comandos de calidad garantizada para la interoperabilidad
- **Perspicaz**: un hermoso tablero de interfaz web con capacidad de respuesta para ver y controlar su Pi-hole
- **Versátil**: puede funcionar opcionalmente como [servidor DHCP](https://discourse.pi-hole.net/t/how-do-i-use-pi-holes-built-in-dhcp-server-and-why-would-i-want-to/3026), asegurando que *todos* sus dispositivos estén protegidos automáticamente
- **Escalable**: [capaz de manejar cientos de millones de consultas](https://pi-hole.net/2017/05/24/how-much-traffic-can-pi-hole-handle/) cuando se instala en un hardware de nivel de servidor
- **Moderno**: bloquea los anuncios tanto en IPv4 como en IPv6
- **Gratis**: software de código abierto que ayuda a garantizar que _usted_ es la única persona que controla su privacidad

-----

## Instalación automatizada en un solo paso

Los que quieran empezar de forma rápida y cómoda pueden instalar Pi-hole con el siguiente comando:

### `curl -sSL https://install.pi-hole.net | bash`

## Métodos alternativos de instalación

La canalización a `bash` es [controvertida](https://pi-hole.net/2016/07/25/curling-and-piping-to-bash), ya que impide [leer el código que está a punto de ejecutarse](https://github.com/pi-hole/pi-hole/blob/master/automated%20install/basic-install.sh) en su sistema. Por lo tanto, ofrecemos estos métodos de instalación alternativos que permiten la revisión del código antes de la instalación:


### Método 1: Clonar nuestro repositorio y ejecutar

```bash
git clone --depth 1 https://github.com/pi-hole/pi-hole.git Pi-hole
cd "Pi-hole/automated install/"
sudo bash basic-install.sh
```

### Método 2: Descargue manualmente el instalador y ejecute

```bash
wget -O basic-install.sh https://install.pi-hole.net
sudo bash basic-install.sh
```
### Método 3: Usar Docker para desplegar Pi-hole
Por favor, consulte el [Pi-hole docker repo](https://github.com/pi-hole/docker-pi-hole) para utilizar las imágenes Docker oficiales.

## [Post-instalación: Haga que su red se aproveche de Pi-hole](https://docs.pi-hole.net/main/post-install/)

Una vez ejecutado el instalador, deberás [configurar tu router para que **los clientes DHCP usen Pi-hole como su servidor DNS**](https://discourse.pi-hole.net/t/how-do-i-configure-my-devices-to-use-pi-hole-as-their-dns-server/245) lo que asegura que todos los dispositivos que se conecten a tu red tendrán el contenido bloqueado sin ninguna intervención adicional.

Si tu router no soporta la configuración del servidor DNS, puedes [usar el servidor DHCP incorporado en Pi-hole](https://discourse.pi-hole.net/t/how-do-i-use-pi-holes-built-in-dhcp-server-and-why-would-i-want-to/3026); sólo asegúrate de desactivar primero el DHCP en tu router (si tiene esa función disponible).

Como último recurso, siempre puedes configurar manualmente cada dispositivo para que utilice Pi-hole como su servidor DNS.

-----

## Pi-hole es gratis, pero se alimenta de tu apoyo

El mantenimiento de un software libre, de código abierto y respetuoso con la privacidad conlleva muchos costes recurrentes, gastos que [nuestros desarrolladores voluntarios](https://github.com/orgs/pi-hole/people) sufragan de su propio bolsillo. Este es sólo un ejemplo de lo mucho que nos importa nuestro software, así como de la importancia de mantenerlo.

No te equivoques: **Tu apoyo es absolutamente vital para ayudarnos a seguir innovando.


### [Donaciones](https://pi-hole.net/donate)

El envío de una donación mediante nuestro Botón de Patrocinio es **extremadamente útil** para compensar una parte de nuestros gastos mensuales y recompensar a nuestro dedicado equipo de desarrollo:

### Apoyo alternativo

Si prefieres no donar (¡no pasa nada!), hay otras formas de ayudarnos:

- [Patrocinadores de GitHub](https://github.com/sponsors/pi-hole/)
- [Patreon](https://patreon.com/pihole)
- [Hetzner Cloud](https://hetzner.cloud/?ref=7aceisRX3AzA) _enlace de afiliación_
- [Digital Ocean](https://www.digitalocean.com/?refcode=344d234950e1) _enlace de afiliación_
- [Stickermule](https://www.stickermule.com/unlock?ref_id=9127301701&utm_medium=link&utm_source=invite) _obtenga un crédito de 10 dólares tras su primera compra_
- [Amazon US](http://www.amazon.com/exec/obidos/redirect-home/pihole09-20) _enlace de afiliación_
- Correr la voz sobre nuestro software, y cómo te has beneficiado de él


### Contribuyendo a través de GitHub

Damos la bienvenida a _todos_ para que contribuyan con informes de problemas, sugieran nuevas características y creen solicitudes de extracción.

Si tienes algo que añadir, desde un error tipográfico hasta una nueva función, estaremos encantados de comprobarlo. Asegúrate de rellenar nuestra plantilla cuando envíes tu solicitud; las preguntas que plantea ayudarán a los voluntarios a entender rápidamente lo que pretendes conseguir.

Encontrarás que el [script de instalación](https://github.com/pi-hole/pi-hole/blob/master/automated%20install/basic-install.sh) y el [script de depuración](https://github.com/pi-hole/pi-hole/blob/master/advanced/Scripts/piholeDebug.sh) tienen una gran cantidad de comentarios, que te ayudarán a entender mejor cómo funciona Pi-hole. También son un recurso valioso para aquellos que quieren aprender a escribir scripts o codificar un programa. Animamos a cualquiera que le guste trastear a que lo lea y envíe un pull request para que lo revisemos.

-----

## Cómo ponerse en contacto con nosotros

Aunque se nos puede contactar principalmente en nuestro [Foro de Usuarios de Discourse](https://discourse.pi-hole.net/), también se nos puede encontrar en una variedad de medios sociales.

**Por favor, asegúrese de revisar las preguntas frecuentes** antes de iniciar una nueva discusión. Muchas de las preguntas de los usuarios ya tienen respuesta y pueden ser resueltas sin necesidad de ayuda adicional.

- [Preguntas frecuentes](https://discourse.pi-hole.net/c/faqs)
- [Solicitudes de características](https://discourse.pi-hole.net/c/feature-requests?order=votes)
- [Reddit](https://www.reddit.com/r/pihole/)
- [Twitter](https://twitter.com/The_Pi_hole)

-----

## Desglose de características

### [Motor más rápido que la luz](https://github.com/pi-hole/ftl)

[FTLDNS](https://github.com/pi-hole/ftl) es un demonio ligero, construido con el propósito de proporcionar las estadísticas necesarias para la Interfaz Web, y su API se puede integrar fácilmente en sus propios proyectos. Como su nombre indica, FTLDNS hace todo esto *muy rápidamente*.

Algunas de las estadísticas que puede integrar incluyen:

- Número total de dominios bloqueados
- Número total de consultas DNS hoy
- Número total de anuncios bloqueados hoy
- Porcentaje de anuncios bloqueados
- Dominios únicos
- Consultas reenviadas (al servidor DNS de entrada elegido)
- Consultas en caché
- Clientes únicos

Se puede acceder a la API a través de [`telnet`](https://github.com/pi-hole/FTL), la web (`admin/api.php`) y la línea de comandos (`pihole -c -j`). Puedes encontrar [más detalles aquí](https://discourse.pi-hole.net/t/pi-hole-api/1863).

### La Interfaz de Línea de Comandos

El comando [pihole](https://docs.pi-hole.net/core/pihole-command/) tiene toda la funcionalidad necesaria para poder administrar completamente el Pi-hole, sin necesidad de la Interfaz Web. Es rápido, fácil de usar y auditable por cualquier persona con conocimientos de `bash`.

Algunas características notables incluyen:

- [Listas blancas, listas negras y Regex](https://docs.pi-hole.net/core/pihole-command/#whitelisting-blacklisting-and-regex)
- [Utilidad de depuración](https://docs.pi-hole.net/core/pihole-command/#debugger)
- [Visualización del archivo de registro en vivo](https://docs.pi-hole.net/core/pihole-command/#tail)
- [Actualización de listas de anuncios](https://docs.pi-hole.net/core/pihole-command/#gravity)
- [Consulta de las listas de anuncios para los dominios bloqueados](https://docs.pi-hole.net/core/pihole-command/#query)
- [Activación y desactivación de Pi-hole](https://docs.pi-hole.net/core/pihole-command/#enable-disable)
- ¡... y *mucho* más!

Puede leer nuestro [Desglose de características principales](https://docs.pi-hole.net/core/pihole-command/#pi-hole-core) para obtener más información.

### El panel de la interfaz web

Este [tablero opcional](https://github.com/pi-hole/AdminLTE) le permite ver las estadísticas, cambiar los ajustes y configurar su Pi-hole. Es el poder de la interfaz de línea de comandos, sin la curva de aprendizaje.

Algunas características notables incluyen:

- Interfaz móvil amigable
- Protección con contraseña
- Gráficos detallados y tablas de donuts
- Listas de dominios y clientes
- Un registro de consultas filtrable y clasificable
- Estadísticas a largo plazo para ver los datos en rangos de tiempo definidos por el usuario
- La posibilidad de gestionar y configurar fácilmente las características de Pi-hole
- ... ¡y todas las funciones principales de la interfaz de línea de comandos!

Hay varias maneras de [acceder al tablero](https://discourse.pi-hole.net/t/how-do-i-access-pi-holes-dashboard-admin-interface/3168):

1. `http://pi.hole/admin/` (cuando usas Pi-hole como tu servidor DNS)
2. `http://<IP_ADDPRESS_OF_YOUR_PI_HOLE>/admin/`
