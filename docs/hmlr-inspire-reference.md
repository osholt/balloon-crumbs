# HM Land Registry INSPIRE reference layer

## Product decision

Balloon Crumbs may show HM Land Registry (HMLR) INSPIRE Index Polygons as an
optional, neutral reference near a proposed landing zone. The layer is useful
for discussing the indicative extent of some registered freehold properties in
England and Wales. It is not a landowner directory and it is never evidence of
permission to enter.

The public layer must remain visually and technically separate from encrypted
crew access notes. INSPIRE polygons are always neutral blue. A cooperative or
uncooperative outcome can only come from a separately entered private access
note; it must never be inferred from HMLR data.

HMLR documents these limitations:

- polygons show the indicative extent and location of registered freehold
  properties, not the exact legal boundary;
- the dataset does not identify the registered proprietor;
- leasehold and other interests are not a complete part of this reference;
- no returned polygon, or no polygon being returned, says nothing about access
  permission or whether every interest in the land is registered;
- HMLR supplies this dataset for England and Wales, not Scotland or Northern
  Ireland.

Authoritative product and technical guidance:

- <https://www.gov.uk/guidance/inspire-index-polygons-spatial-data>
- <https://use-land-property-data.service.gov.uk/datasets/inspire>
- <https://use-land-property-data.service.gov.uk/datasets/inspire/tech-guidance>

## Licence and attribution

The source is made available under the Open Government Licence subject to the
HMLR conditions published with the dataset. Each response and the app
information sheet carry the required attribution for the installed dataset
year:

> This information is subject to Crown copyright and database rights [year] and
> is reproduced with the permission of HM Land Registry.

> The polygons (including the associated geometry, namely x, y co-ordinates)
> are subject to Crown copyright and database rights [year] Ordnance Survey
> AC0000851063.

Before an operator installs an update, they must re-read the current conditions
at <https://use-land-property-data.service.gov.uk/datasets/inspire/#conditions>.
Do not redistribute the downloaded GML or generated national index outside the
private relay deployment merely because this application can display bounded
results.

## Privacy and data minimisation

The downloadable source has no proprietor name. The index builder nevertheless
uses an allow-list: it retains only the INSPIRE identifier and WGS84 polygon
geometry. Every other source attribute is discarded. The public API returns at
most 100 features and 256 KiB of geometry within a 25–2,000 metre lookup radius.

The app sends the selected landing-zone centre, or the crew's current position
when no zone exists, only after the crew explicitly turns the layer on. The
production relay disables request access logs so those query coordinates are not
written to its normal HTTP log. Metrics contain only aggregate outcomes. The
app does not persist a downloaded response.

## Monthly installation and removal

HMLR normally publishes one GML download per local authority, updated monthly.
The source uses British National Grid (EPSG:27700). Convert the required current
downloads to WGS84 GeoJSON Sequence with GDAL, then build the atomic read-only
index:

```bash
ogr2ogr -f GeoJSONSeq -t_srs EPSG:4326 somerset.geojsonseq somerset.gml

cd apps/server
uv run balloon-crumbs-build-inspire \
  ../../imports/*.geojsonseq \
  --output ../../deploy/maps/data/hmlr/current.sqlite \
  --dataset-date 2026-08-02
```

For national coverage, convert every current England and Wales local-authority
download in the same batch. HMLR warns that reprojection can displace displayed
geometry, which is another reason the UI must not describe the result as an
exact boundary.

The builder validates coordinate bounds, geometry size and point count and
atomically replaces `current.sqlite`; a failed build leaves the prior index in
place. After replacement, smoke-test a known coordinate:

```bash
curl --fail --get \
  --data-urlencode latitude=51.4545 \
  --data-urlencode longitude=-2.5879 \
  --data-urlencode radiusMetres=500 \
  https://relay.example.com/api/v1/reference/inspire
```

Set the GitHub repository variable `BALLOON_CRUMBS_HMLR_INSPIRE_ENABLED=true`
only after the live relay index has passed that check. Monthly index replacement
then needs no mobile release. To withdraw the layer immediately, set that
variable false for subsequent builds and remove
`deploy/maps/data/hmlr/current.sqlite` from the relay; requests fail closed with
503 while the road map and private notes continue to work.

The generated database and raw downloads are ignored by Git and must never be
committed.
